import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';

class ScheduleLibrary {
  final List<ScheduleProfile> profiles;
  final String activeId;

  const ScheduleLibrary({required this.profiles, required this.activeId});

  bool get isEmpty => profiles.every((profile) => profile.isEmpty);

  String encode({bool pretty = false}) {
    final data = {
      'version': 3,
      'activeId': activeId,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  static bool isBackup(Object? value) =>
      value is Map<String, dynamic> &&
      (value.containsKey('profiles') ||
          value.containsKey('version') ||
          (value['config'] is Map && value['courses'] is List));

  factory ScheduleLibrary.fromBackup(Object? data) {
    if (data is Map<String, dynamic> && data['version'] == 3) {
      final entries = data['profiles'] as List<dynamic>;
      final profiles = entries.map((item) {
        final entry = item as Map<String, dynamic>;
        final config = entry['config'];
        if (entry['id'] is! String ||
            entry['name'] is! String ||
            entry['courses'] is! List ||
            config is! Map<String, dynamic>) {
          throw const FormatException('备份缺少档案信息');
        }
        final start = config['semesterStart'];
        if (start is! String ||
            DateTime.tryParse(start) == null ||
            config['totalWeeks'] is! int ||
            config['maxSections'] is! int ||
            config['sectionTimes'] is! List) {
          throw const FormatException('备份缺少有效的开学日期或作息设置');
        }
        return ScheduleProfile.fromJson(entry);
      }).toList();
      return _validated(profiles, data['activeId'] as String);
    }

    if (data is List<dynamic>) {
      data = <String, dynamic>{'courses': data};
    }
    if (data is Map<String, dynamic> &&
        (data['version'] == null ||
            data['version'] == 1 ||
            data['version'] == 2) &&
        data['courses'] is List) {
      const id = 'legacy_backup';
      return _validated([
        ScheduleProfile.fromJson({
          ...data,
          'id': id,
          'name': data['name'] ?? '恢复的课表',
        }),
      ], id);
    }
    throw const FormatException('不支持的 JSON 备份格式');
  }

  static ScheduleLibrary _validated(
    List<ScheduleProfile> profiles,
    String activeId,
  ) {
    final ids = <String>{};
    for (final profile in profiles) {
      if (profile.id.isEmpty ||
          !ids.add(profile.id) ||
          profile.config.totalWeeks < 1 ||
          profile.config.maxSections < 1) {
        throw const FormatException('课表档案或学期配置不正确');
      }
      final courseIds = profile.courses.map((course) => course.id).toSet();
      final sources = <(String, String)>{};
      for (final adjustment in profile.adjustments) {
        if (!courseIds.add(adjustment.id) ||
            adjustment.course.startSection < 1 ||
            adjustment.course.sectionCount < 1 ||
            (adjustment.isMove &&
                !sources.add((
                  adjustment.originalCourseId!,
                  ScheduleConfig.dateKey(adjustment.originalDate!),
                )))) {
          throw const FormatException('备份中的单次调课有冲突');
        }
      }
    }
    if (!ids.contains(activeId)) {
      throw const FormatException('备份缺少当前选中的课表');
    }
    return ScheduleLibrary(profiles: profiles, activeId: activeId);
  }

  /// 将备份恢复为独立档案，包括原来选中的课表。
  ScheduleLibrary withRestored(ScheduleLibrary backup) {
    final ids = {for (final profile in profiles) profile.id};
    final names = {for (final profile in profiles) profile.name};
    final restored = <ScheduleProfile>[];
    final prefix = 'restored_${DateTime.now().microsecondsSinceEpoch}';
    var index = 0;
    var restoredActiveId = '';
    for (final profile in backup.profiles) {
      String id;
      do {
        id = '${prefix}_${index++}';
      } while (!ids.add(id));

      final baseName = profile.name;
      var name = baseName;
      var suffix = 1;
      while (!names.add(name)) {
        name = suffix == 1 ? '$baseName（恢复）' : '$baseName（恢复 $suffix）';
        suffix++;
      }
      restored.add(profile.copyWith(id: id, name: name));
      if (profile.id == backup.activeId) restoredActiveId = id;
    }
    return ScheduleLibrary(
      profiles: [...profiles, ...restored],
      activeId: restoredActiveId,
    );
  }
}

class ScheduleRecoveryRequired implements Exception {
  final String raw;
  final ScheduleLibrary? previous;

  const ScheduleRecoveryRequired({required this.raw, this.previous});
}

/// 一次保存写入完整档案和选中状态，读不到当前存档时保留原内容。
class StorageService {
  static const _legacyCoursesKey = 'saved_courses_v1';
  static const _legacyConfigKey = 'saved_schedule_config_v1';
  static const _profilesKey = 'saved_profiles_v2';
  static const _activeProfileIdKey = 'active_profile_id_v2';
  static const _libraryKey = 'schedule_library_v3';
  static const _previousKey = 'schedule_library_v3_previous';
  static const _recoveryKey = 'schedule_library_v3_recovery';
  static const _widgetHintKey = 'first_import_widget_hint_shown';

  Future<void> _writes = Future<void>.value();

  Future<ScheduleLibrary> loadAllProfiles() async {
    await _writes;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_libraryKey);

    if (raw != null) {
      final library = _readSnapshot(raw);
      if (library != null) return library;
      throw ScheduleRecoveryRequired(
        raw: raw is String ? raw : jsonEncode(raw),
        previous: _readSnapshot(prefs.get(_previousKey)),
      );
    }

    final ScheduleLibrary library;
    try {
      library = _readLegacy(prefs);
    } on Object {
      throw ScheduleRecoveryRequired(
        raw: const JsonEncoder.withIndent('  ').convert({
          for (final key in [
            _profilesKey,
            _activeProfileIdKey,
            _legacyCoursesKey,
            _legacyConfigKey,
          ])
            if (prefs.containsKey(key)) key: prefs.get(key),
        }),
        previous: _readSnapshot(prefs.get(_previousKey)),
      );
    }
    await saveAllProfiles(
      profiles: library.profiles,
      activeId: library.activeId,
    );
    return library;
  }

  ScheduleLibrary _readLegacy(SharedPreferences prefs) {
    final rawProfiles = prefs.getString(_profilesKey);
    if (rawProfiles != null) {
      final entries = jsonDecode(rawProfiles) as List<dynamic>;
      final profiles = entries
          .map((item) => ScheduleProfile.fromJson(item as Map<String, dynamic>))
          .toList();
      if (profiles.isEmpty) throw const FormatException('课表档案为空');
      final savedId = prefs.getString(_activeProfileIdKey);
      return ScheduleLibrary._validated(
        profiles,
        profiles.any((profile) => profile.id == savedId)
            ? savedId!
            : profiles.first.id,
      );
    }

    final courses = prefs.getString(_legacyCoursesKey);
    final config = prefs.getString(_legacyConfigKey);
    const id = 'default_profile';
    return ScheduleLibrary._validated([
      ScheduleProfile(
        id: id,
        name: '默认课表',
        courses: courses == null
            ? []
            : (jsonDecode(courses) as List<dynamic>)
                  .map((item) => Course.fromJson(item as Map<String, dynamic>))
                  .toList(),
        config: config == null
            ? ScheduleConfig.defaults()
            : ScheduleConfig.fromJson(
                jsonDecode(config) as Map<String, dynamic>,
              ),
      ),
    ], id);
  }

  ScheduleLibrary? _readSnapshot(Object? raw) {
    if (raw is! String) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['version'] != 3) return null;
      return ScheduleLibrary.fromBackup(data);
    } on Object {
      return null;
    }
  }

  Future<void> saveAllProfiles({
    required List<ScheduleProfile> profiles,
    required String activeId,
    ScheduleRecoveryRequired? recovery,
  }) {
    final encoded = ScheduleLibrary._validated(profiles, activeId).encode();
    final save = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(_libraryKey);
      if (recovery != null) {
        await _write(prefs, _recoveryKey, recovery.raw);
      } else if (raw != null) {
        if (_readSnapshot(raw) == null) {
          throw ScheduleRecoveryRequired(
            raw: raw is String ? raw : jsonEncode(raw),
            previous: _readSnapshot(prefs.get(_previousKey)),
          );
        }
        await _write(prefs, _previousKey, raw as String);
      }
      await _write(prefs, _libraryKey, encoded);
    });
    _writes = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return save;
  }

  Future<void> _write(SharedPreferences prefs, String key, String value) async {
    if (!await prefs.setString(key, value)) {
      await prefs.reload();
      throw StateError('无法保存课表');
    }
  }

  Future<bool> takeFirstImportWidgetHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_widgetHintKey) == true) return false;
    return prefs.setBool(_widgetHintKey, true);
  }
}
