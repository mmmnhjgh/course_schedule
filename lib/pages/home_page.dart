import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/course_adjustment.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import '../services/ai_import_service.dart';
import '../services/file_import_service.dart';
import '../services/schedule_occurrences.dart';
import '../services/storage_service.dart';
import '../services/widget_sync_service.dart';
import '../widgets/course_detail_sheet.dart';
import '../widgets/course_adjustment_sheet.dart';
import '../widgets/course_edit_sheet.dart';
import '../widgets/import_preview_sheet.dart';
import 'ai_import_page.dart';
import 'settings_page.dart';
import 'today_page.dart';
import 'web_import_page.dart';
import 'week_page.dart';

/// 主页面外壳：持有全部课表档案、多源导入流程与底部导航
class HomePage extends StatefulWidget {
  final void Function(int colorValue, String themeMode) onAppearanceChanged;

  const HomePage({
    super.key,
    required this.onAppearanceChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _storage = StorageService();
  ScheduleLibrary _library = const ScheduleLibrary(profiles: [], activeId: '');
  List<ScheduleProfile> get _profiles => _library.profiles;
  String get _activeProfileId => _library.activeId;

  int _tabIndex = 1;
  bool _isLoading = true;
  bool _saving = false;
  ScheduleRecoveryRequired? _recovery;
  Object? _loadError;
  DateTime _now = DateTime.now();
  Timer? _clock;

  ScheduleProfile get _activeProfile => _profiles.firstWhere(
        (p) => p.id == _activeProfileId,
        orElse: () => _profiles.first,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    WidgetSyncService.setOnOpenTabListener((tab) {
      if (mounted && tab >= 0 && tab <= 2) {
        setState(() => _tabIndex = tab);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    WidgetSyncService.setOnOpenTabListener(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _clock?.cancel();
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now());
      _startClock();
      unawaited(WidgetSyncService.refreshWidgets());
    }
  }

  void _startClock() {
    _clock?.cancel();
    final now = DateTime.now();
    _clock = Timer(
      Duration(milliseconds: 60000 - now.second * 1000 - now.millisecond),
      () {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
        _startClock();
      },
    );
  }

  Future<void> _loadData() async {
    try {
      final loaded = await _storage.loadAllProfiles();
      final initialTab = await WidgetSyncService.consumeInitialTab();
      if (!mounted) return;
      setState(() {
        _library = loaded;
        if (initialTab != null && initialTab >= 0 && initialTab <= 2) {
          _tabIndex = initialTab;
        }
        _isLoading = false;
      });
      await _showActiveProfile();
    } on ScheduleRecoveryRequired catch (error) {
      if (!mounted) return;
      setState(() {
        _recovery = error;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _showActiveProfile() async {
    final current = _activeProfile;
    widget.onAppearanceChanged(
      current.config.themeColorValue,
      current.config.themeMode,
    );
    await WidgetSyncService.syncProfile(current);
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<bool> _saveLibrary(
    ScheduleLibrary next, {
    ScheduleRecoveryRequired? recovery,
  }) async {
    if (_saving) {
      _showMessage('正在保存课表，请稍后再试');
      return false;
    }
    setState(() => _saving = true);
    try {
      try {
        await _storage.saveAllProfiles(
          profiles: next.profiles,
          activeId: next.activeId,
          recovery: recovery,
        );
      } catch (_) {
        _showMessage('保存失败，原课表已保留。请再试一次。');
        return false;
      }
      if (!mounted) return false;
      setState(() {
        _library = next;
        _recovery = null;
      });
      await _showActiveProfile();
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _requestPinWidget(String type) async {
    await WidgetSyncService.syncProfile(_activeProfile);
    if (!mounted) return false;
    return WidgetSyncService.requestPinWidget(type);
  }

  Future<bool> _replaceActiveProfile(ScheduleProfile updated) async {
    if (updated.id != _activeProfileId) return false;
    return _saveLibrary(
      ScheduleLibrary(
        profiles: [
          for (final profile in _profiles)
            if (profile.id == updated.id) updated else profile,
        ],
        activeId: updated.id,
      ),
    );
  }

  bool _isCurrentProfile(ScheduleProfile profile) {
    if (!mounted) return false;
    if (identical(profile, _activeProfile)) return true;
    _showMessage('当前课表已变化，请重新打开操作');
    return false;
  }

  CourseAdjustment? _adjustmentFor(Course course, DateTime date) {
    final key = ScheduleConfig.dateKey(date);
    for (final item in _activeProfile.adjustments) {
      if (item.id == course.id && ScheduleConfig.dateKey(item.date) == key) {
        return item;
      }
    }
    return null;
  }

  bool _canMove(Course course, DateTime date) {
    final week = _activeProfile.config.teachingWeek(date);
    return week != null &&
        course.weekday == date.weekday &&
        course.isActiveInWeek(week) &&
        !course.isCanceledInWeek(week);
  }

  Future<void> _openCourseGroupDetail(List<Course> group, DateTime date) async {
    final profile = _activeProfile;
    final action = await showCourseDetailSheet(
      context,
      courses: group,
      config: profile.config,
      canAdjust: (course) =>
          _adjustmentFor(course, date) == null && _canMove(course, date),
      adjustmentLabel: (course) {
        final adjustment = _adjustmentFor(course, date);
        return adjustment == null
            ? null
            : adjustment.isMove
            ? '调课'
            : '补课';
      },
    );
    if (action == null || !_isCurrentProfile(profile)) return;

    switch (action) {
      case CourseDetailEdit(:final course):
        final adjustment = _adjustmentFor(course, date);
        if (adjustment != null) {
          await _openAdjustment(date, existing: adjustment);
        } else {
          await _openAddOrEditCourse(existing: course);
        }
      case CourseDetailDelete(:final course):
        final adjustment = _adjustmentFor(course, date);
        if (adjustment != null) {
          await _removeAdjustment(adjustment);
        } else {
          await _deleteCourse(course);
        }
      case CourseDetailAdjust(:final course):
        await _openAdjustment(date, original: course);
    }
  }

  Future<void> _deleteCourse(Course course) async {
    final profile = _activeProfile;
    final linked = profile.adjustments.where(
      (item) => item.originalCourseId == course.id,
    );
    if (linked.isNotEmpty) {
      final confirmed = await _confirm(
        '删除课程',
        '这门课和关联的 ${linked.length} 次调课都会删除。',
        '删除',
      );
      if (!confirmed || !_isCurrentProfile(profile)) return;
    }
    await _replaceActiveProfile(
      profile.copyWith(
        courses: profile.courses.where((item) => item.id != course.id).toList(),
        adjustments: profile.adjustments
            .where((item) => item.originalCourseId != course.id)
            .toList(),
      ),
    );
  }

  Future<bool> _confirm(String title, String description, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _openAdjustment(
    DateTime date, {
    Course? original,
    CourseAdjustment? existing,
  }) async {
    final profile = _activeProfile;
    final adjustment = await showCourseAdjustmentSheet(
      context,
      profile: profile,
      date: date,
      original: original,
      existing: existing,
    );
    if (adjustment == null || !_isCurrentProfile(profile)) return;
    final adjustments = [
      for (final current in profile.adjustments)
        if (current.id != adjustment.id) current,
      adjustment,
    ];
    if (await _replaceActiveProfile(
      profile.copyWith(adjustments: adjustments),
    )) {
      _showMessage('已保存这次安排');
    }
  }

  Future<void> _removeAdjustment(CourseAdjustment adjustment) async {
    final profile = _activeProfile;
    final title = adjustment.isMove ? '撤销调课' : '删除补课';
    final description = adjustment.isMove
        ? '撤销后，原日期的课会按原课表显示。'
        : '这次补课将从课表中移除。';
    if (!await _confirm(title, description, title) ||
        !_isCurrentProfile(profile)) {
      return;
    }
    await _replaceActiveProfile(
      profile.copyWith(
        adjustments: profile.adjustments
            .where((item) => item.id != adjustment.id)
            .toList(),
      ),
    );
  }

  Future<void> _manageAdjustments() async {
    final profile = _activeProfile;
    final timetable = ScheduleOccurrences(profile);
    final items = [...profile.adjustments]
      ..sort((a, b) => a.date.compareTo(b.date));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('单次调课与补课', style: Theme.of(sheetContext).textTheme.titleLarge),
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('添加一次补课'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openAdjustment(_now);
              },
            ),
            for (final item in items)
              ListTile(
                title: Text(item.course.name),
                subtitle: Text(
                  '${ScheduleConfig.dateKey(item.date)} · 第 ${item.course.startSection}–${item.course.endSection} 节'
                  '${timetable.isValidTarget(item) ? "" : " · 待处理（日期或节次超出范围）"}',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openAdjustment(item.date, existing: item);
                },
                trailing: IconButton(
                  icon: Icon(item.isMove ? Icons.undo : Icons.delete_outline),
                  tooltip: item.isMove ? '撤销调课' : '删除补课',
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _removeAdjustment(item);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 周视图长按课程卡片：弹出快捷菜单（标记本周停课/恢复、编辑、删除）
  Future<void> _onLongPressCourse(Course course, int week) async {
    final date = _activeProfile.config.dateOf(week, course.weekday);
    if (_adjustmentFor(course, date) != null) {
      await _openCourseGroupDetail([course], date);
      return;
    }
    final isCanceled = course.isCanceledInWeek(week);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(course.colorValue),
                radius: 14,
              ),
              title: Text(
                course.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('第 $week 周 · 第${course.startSection}-${course.endSection}节'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isCanceled ? Icons.restore : Icons.event_busy_outlined,
              ),
              title: Text(isCanceled ? '恢复第 $week 周上课' : '标记第 $week 周停课 / 请假'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                final nextCanceled = {...course.canceledWeeks};
                if (isCanceled) {
                  nextCanceled.remove(week);
                } else {
                  nextCanceled.add(week);
                }
                final updated = course.copyWith(
                  canceledWeeks: nextCanceled.toList()..sort(),
                  userEdited: true,
                );
                final list = _activeProfile.courses
                    .map((c) => c.id == course.id ? updated : c)
                    .toList();
                _replaceActiveProfile(_activeProfile.copyWith(courses: list));
              },
            ),
            if (_canMove(course, date))
              ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('只调整这一次'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openAdjustment(date, original: course);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑课程'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openAddOrEditCourse(existing: course);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除该课程', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _deleteCourse(course);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddOrEditCourse({
    Course? existing,
    int weekday = 1,
    int startSection = 1,
  }) async {
    final profile = _activeProfile;
    final result = await showCourseEditSheet(
      context,
      initialCourse: existing,
      initialWeekday: weekday,
      initialStartSection: startSection,
      totalWeeks: _activeProfile.config.totalWeeks,
      maxSections: _activeProfile.config.maxSections,
      sectionTimes: _activeProfile.config.sectionTimes,
    );
    if (result == null || !_isCurrentProfile(profile)) return;

    final currentCourses = [..._activeProfile.courses];
    if (result.deleted && existing != null) {
      await _deleteCourse(existing);
      return;
    } else if (result.course != null) {
      final idx = currentCourses.indexWhere((c) => c.id == result.course!.id);
      if (idx >= 0) {
        currentCourses[idx] = result.course!;
      } else {
        currentCourses.add(result.course!);
      }
    }
    await _replaceActiveProfile(profile.copyWith(courses: currentCourses));
  }

  void _updateConfig(ScheduleConfig newConfig) {
    _replaceActiveProfile(_activeProfile.copyWith(config: newConfig));
  }

  Future<void> _previewAndApplyImport(ImportPayload payload) async {
    if (!mounted || payload.courses.isEmpty) {
      if (mounted) _showMessage(payload.warnings.firstOrNull ?? '未识别到有效课程');
      return;
    }
    final profile = _activeProfile;
    final first = _library.isEmpty;
    final next = await showImportPreviewSheet(
      context,
      payload: payload,
      profile: profile,
    );
    if (next == null || !_isCurrentProfile(profile)) return;
    if (await _replaceActiveProfile(next) && mounted) {
      setState(() => _tabIndex = 1);
      await _showImportSuccess('导入完成，当前共 ${next.courses.length} 门课程', first);
    }
  }

  Future<void> _showImportSuccess(String message, bool first) async {
    var showWidgetHint = false;
    if (first && !_library.isEmpty) {
      try {
        showWidgetHint = await _storage.takeFirstImportWidgetHint();
      } catch (_) {
        // 导入已保存，设备提示的保存失败不影响结果。
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: showWidgetHint ? 8 : 4),
        action: showWidgetHint
            ? SnackBarAction(
                label: '添加桌面小组件',
                onPressed: () =>
                    showDesktopWidgetSheet(context, _requestPinWidget),
              )
            : null,
      ),
    );
  }

  Future<void> _chooseImportSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('教务系统网页'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openWebImport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('课表文件或备份'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importFromFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 转换导入'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openAiImport();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWebImport() async {
    final profile = _activeProfile;
    final payload = await Navigator.of(context).push<ImportPayload>(
      MaterialPageRoute(
        builder: (_) => WebImportPage(
          maxWeeks: profile.config.totalWeeks,
          maxSections: profile.config.maxSections,
        ),
      ),
    );
    if (payload != null && _isCurrentProfile(profile)) {
      await _previewAndApplyImport(payload);
    }
  }

  Future<void> _openAiImport() async {
    final profile = _activeProfile;
    final payload = await Navigator.of(context).push<ImportPayload>(
      MaterialPageRoute(
        builder: (_) => AiImportPage(
          maxWeeks: profile.config.totalWeeks,
          maxSections: profile.config.maxSections,
        ),
      ),
    );
    if (payload != null && _isCurrentProfile(profile)) {
      await _previewAndApplyImport(payload);
    }
  }

  Future<void> _importFromFile({bool backupOnly = false}) async {
    try {
      final profile = _profiles.isEmpty ? null : _activeProfile;
      final config = profile?.config ?? ScheduleConfig.defaults();
      final result = await FileImportService.pickAndParseFile(
        currentConfig: config,
        backupOnly: backupOnly,
      );
      if (!mounted || result == null) return;
      if (result.payload != null &&
          (profile == null || !_isCurrentProfile(profile))) {
        return;
      }
      await _applyFileImport(result);
    } catch (error) {
      _showMessage('文件导入失败：$error');
    }
  }

  Future<void> _applyFileImport(FileImportResult result) async {
    final backup = result.backup;
    final payload = result.payload;
    if (backup != null) {
      await _restoreBackup(backup);
    } else if (payload != null) {
      await _previewAndApplyImport(payload);
    }
  }

  Future<void> _restoreBackup(ScheduleLibrary backup) async {
    final recovery = _recovery;
    final baseline = recovery?.previous ?? _library;
    final message = '将恢复 ${backup.profiles.length} 张课表。设备上已有的课表会保留。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复为新课表'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 8),
                for (final profile in backup.profiles)
                  Text('• ${profile.name}（${profile.courses.length} 门课）'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (!identical(baseline, _recovery?.previous ?? _library)) {
      _showMessage('当前课表已变化，请重新预览备份');
      return;
    }
    final restored = baseline.withRestored(backup);
    if (await _saveLibrary(restored, recovery: recovery) && mounted) {
      setState(() => _tabIndex = 1);
      await _showImportSuccess(
        '已恢复 ${backup.profiles.length} 张课表',
        baseline.isEmpty,
      );
    }
  }

  Future<void> _exportRawStorage(ScheduleRecoveryRequired recovery) async {
    try {
      await FileImportService.shareTextAsFile(
        filename: '轻课表原始存档.txt',
        content: recovery.raw,
        shareSubject: '轻课表原始存档',
      );
    } catch (error) {
      _showMessage('导出失败：$error');
    }
  }

  Widget _buildRecoveryPage(ScheduleRecoveryRequired recovery) {
    final previous = recovery.previous;
    return Scaffold(
      appBar: AppBar(title: const Text('恢复课表存档')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('当前存档无法读取。原始数据已保留。'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _exportRawStorage(recovery),
                child: const Text('导出原始存档'),
              ),
              if (previous != null)
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => _saveLibrary(previous, recovery: recovery),
                  child: const Text('恢复上一份有效存档'),
                ),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _importFromFile(backupOnly: true),
                child: const Text('导入有效备份'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportIcsShare() async {
    if (ScheduleOccurrences(_activeProfile).all.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前课表还没有课程可导出')));
      return;
    }
    try {
      final ics = FileImportService.exportIcs(
        courses: _activeProfile.courses,
        config: _activeProfile.config,
        scheduleName: _activeProfile.name,
        adjustments: _activeProfile.adjustments,
      );
      await FileImportService.shareTextAsFile(
        filename: '${_activeProfile.name}.ics',
        content: ics,
        shareSubject: '分享课表：${_activeProfile.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出分享失败：$e')),
      );
    }
  }

  void _switchProfile(String id) {
    if (id == _activeProfileId || !_profiles.any((profile) => profile.id == id)) {
      return;
    }
    _saveLibrary(ScheduleLibrary(profiles: _profiles, activeId: id));
  }

  void _createProfile(String name) {
    final created = ScheduleProfile(
      id: 'profile_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      courses: [],
      config: _activeProfile.config.copyWith(),
    );
    _saveLibrary(
      ScheduleLibrary(profiles: [..._profiles, created], activeId: created.id),
    );
  }

  void _renameActiveProfile(String name) {
    _replaceActiveProfile(_activeProfile.copyWith(name: name));
  }

  void _deleteActiveProfile() {
    if (_profiles.length <= 1) return;
    final remaining = _profiles
        .where((profile) => profile.id != _activeProfileId)
        .toList();
    _saveLibrary(
      ScheduleLibrary(profiles: remaining, activeId: remaining.first.id),
    );
  }

  Future<void> _importBackupJson(String jsonText) async {
    try {
      await _applyFileImport(
        FileImportService.parseJsonInput(jsonText, _activeProfile.config),
      );
    } catch (error) {
      _showMessage('JSON 导入失败：$error');
    }
  }

  Future<void> _loadSampleCourses() async {
    final total = _activeProfile.config.totalWeeks;
    final allWeeks = [for (int w = 1; w <= total; w++) w];
    final oddWeeks = [
      for (int w = 1; w <= total; w++)
        if (w.isOdd) w,
    ];
    final evenWeeks = [
      for (int w = 1; w <= total; w++)
        if (w.isEven) w,
    ];

    final samples = [
      Course(
        id: 'sample_1',
        name: '高等数学（上）',
        teacher: '张教授',
        location: '教A-101',
        note: '闭卷考试 · 记得带计算器',
        weekday: 1,
        startSection: 1,
        sectionCount: 2,
        weeks: allWeeks,
        colorValue: 0xFF42A5F5,
      ),
      Course(
        id: 'sample_2',
        name: '大学物理实验',
        teacher: '李老师',
        location: '实验楼-402',
        weekday: 1,
        startSection: 5,
        sectionCount: 3,
        weeks: oddWeeks,
        colorValue: 0xFF26A69A,
      ),
      Course(
        id: 'sample_3',
        name: '大学体育（羽毛球）',
        teacher: '赵老师',
        location: '体育馆二楼',
        weekday: 1,
        startSection: 5,
        sectionCount: 2,
        weeks: evenWeeks,
        colorValue: 0xFFEC407A,
      ),
      Course(
        id: 'sample_4',
        name: '数据结构与算法',
        teacher: '王老师',
        location: '信息楼-205',
        weekday: 2,
        startSection: 3,
        sectionCount: 2,
        weeks: allWeeks,
        colorValue: 0xFFAB47BC,
      ),
      Course(
        id: 'sample_5',
        name: '大学英语听说',
        teacher: '陈老师',
        location: '外语楼-308',
        weekday: 3,
        startSection: 1,
        sectionCount: 2,
        weeks: evenWeeks,
        colorValue: 0xFFFFA726,
      ),
      Course(
        id: 'sample_6',
        name: '移动应用开发实战',
        teacher: '刘老师',
        location: '实训中心-501',
        weekday: 4,
        startSection: 5,
        sectionCount: 2,
        weeks: allWeeks,
        colorValue: 0xFF66BB6A,
      ),
    ];

    final current = _activeProfile;
    if (await _replaceActiveProfile(
      current.copyWith(
        courses: samples,
        adjustments: current.adjustments
            .map((item) => item.asMakeup())
            .toList(),
      ),
    )) {
      _showMessage('已填入示例课表，切到「周课表」看看效果吧！');
    }
  }

  void _clearAllCourses() {
    _replaceActiveProfile(
      _activeProfile.copyWith(courses: [], adjustments: []),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final recovery = _recovery;
    if (recovery != null) return _buildRecoveryPage(recovery);
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('轻课表')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
              _loadData();
            },
            child: const Text('课表暂时无法读取，点击重试'),
          ),
        ),
      );
    }

    final profile = _activeProfile;
    final pages = [
      TodayPage(
        profile: profile,
        now: _now,
        onTapCourse: (course, date) => _openCourseGroupDetail([course], date),
        onAddCourse: () =>
            _openAddOrEditCourse(weekday: _now.weekday, startSection: 1),
      ),
      WeekPage(
        key: ValueKey(profile.id),
        profile: profile,
        now: _now,
        onImport: _chooseImportSource,
        onAddMakeup: _openAdjustment,
        onTapCourseGroup: _openCourseGroupDetail,
        onLongPressCourse: _onLongPressCourse,
        onTapEmptyCell: (weekday, section) => _openAddOrEditCourse(
          weekday: weekday,
          startSection: section,
        ),
      ),
      SettingsPage(
        profiles: _profiles,
        activeProfile: profile,
        onSwitchProfile: _switchProfile,
        onCreateProfile: _createProfile,
        onRenameActiveProfile: _renameActiveProfile,
        onDeleteActiveProfile: _deleteActiveProfile,
        onUpdateConfig: _updateConfig,
        onRequestPinWidget: _requestPinWidget,
        onOpenWebImport: _openWebImport,
        onOpenAiImport: _openAiImport,
        onImportFile: _importFromFile,
        onExportIcsShare: _exportIcsShare,
        onExportJson: () => _library.encode(pretty: true),
        onRestoreBackup: () => _importFromFile(backupOnly: true),
        onManageAdjustments: _manageAdjustments,
        onImportJson: _importBackupJson,
        onLoadSampleCourses: _loadSampleCourses,
        onClearAllCourses: _clearAllCourses,
      ),
    ];

    return Scaffold(
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: '周课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
