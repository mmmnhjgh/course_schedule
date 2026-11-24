import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';

/// 负责把多张课表档案与全局配置保存到手机本地，并支持 JSON 备份导入导出
class StorageService {
  static const _legacyCoursesKey = 'saved_courses_v1';
  static const _legacyConfigKey = 'saved_schedule_config_v1';
  static const _profilesKey = 'saved_profiles_v2';
  static const _activeProfileIdKey = 'active_profile_id_v2';

  /// 读取所有课表档案与当前选中的档案 ID；如为旧版 v1 数据则自动迁移
  Future<({List<ScheduleProfile> profiles, String activeId})>
      loadAllProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rawProfiles = prefs.getString(_profilesKey);

    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfiles) as List<dynamic>;
        final profiles = decoded
            .map((e) => ScheduleProfile.fromJson(e as Map<String, dynamic>))
            .toList();
        if (profiles.isNotEmpty) {
          final savedActiveId = prefs.getString(_activeProfileIdKey);
          final activeId = profiles.any((p) => p.id == savedActiveId)
              ? savedActiveId!
              : profiles.first.id;
          return (profiles: profiles, activeId: activeId);
        }
      } catch (_) {
        // 解析异常时继续尝试迁移或回退默认档案
      }
    }

    // 兼容迁移旧版单课表数据
    final legacyCourses = await _loadLegacyCourses(prefs);
    final legacyConfig = await _loadLegacyConfig(prefs);
    final defaultProfile = ScheduleProfile(
      id: 'default_profile',
      name: '默认课表',
      courses: legacyCourses,
      config: legacyConfig,
    );
    await saveAllProfiles(
      profiles: [defaultProfile],
      activeId: defaultProfile.id,
    );
    return (profiles: [defaultProfile], activeId: defaultProfile.id);
  }

  /// 保存所有课表档案与当前激活 ID
  Future<void> saveAllProfiles({
    required List<ScheduleProfile> profiles,
    required String activeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await Future.wait([
      prefs.setString(_profilesKey, encoded),
      prefs.setString(_activeProfileIdKey, activeId),
    ]);
  }

  Future<List<Course>> _loadLegacyCourses(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyCoursesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => Course.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ScheduleConfig> _loadLegacyConfig(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyConfigKey);
    if (raw == null || raw.isEmpty) return ScheduleConfig.defaults();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ScheduleConfig.fromJson(map);
    } catch (_) {
      return ScheduleConfig.defaults();
    }
  }

  /// 导出单张课表的完整备份（课程 + 配置）为格式化 JSON 字符串
  String exportBackupJson({
    required List<Course> courses,
    required ScheduleConfig config,
  }) {
    final payload = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'config': config.toJson(),
      'courses': courses.map((c) => c.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 从备份 JSON 字符串解析出课程列表和配置（兼容 v1、v2 及纯课程数组）
  ({List<Course> courses, ScheduleConfig? config}) importBackupJson(
    String jsonText,
  ) {
    final decoded = jsonDecode(jsonText);

    if (decoded is List<dynamic>) {
      final courses = decoded
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
      return (courses: courses, config: null);
    }

    if (decoded is Map<String, dynamic>) {
      final rawCourses = decoded['courses'] as List<dynamic>? ?? [];
      final courses = rawCourses
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
      final rawConfig = decoded['config'] as Map<String, dynamic>?;
      final config =
          rawConfig != null ? ScheduleConfig.fromJson(rawConfig) : null;
      return (courses: courses, config: config);
    }

    throw const FormatException('不支持的 JSON 备份格式');
  }
}
