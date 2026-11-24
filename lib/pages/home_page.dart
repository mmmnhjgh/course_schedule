import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import '../services/ai_import_service.dart';
import '../services/file_import_service.dart';
import '../services/import_merge_service.dart';
import '../services/storage_service.dart';
import '../widgets/course_detail_sheet.dart';
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

class _HomePageState extends State<HomePage> {
  final _storage = StorageService();

  int _tabIndex = 1; // 默认打开“周课表”页面
  bool _isLoading = true;
  List<ScheduleProfile> _profiles = [];
  String _activeProfileId = '';

  ScheduleProfile get _activeProfile => _profiles.firstWhere(
        (p) => p.id == _activeProfileId,
        orElse: () => _profiles.first,
      );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final loaded = await _storage.loadAllProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = loaded.profiles;
      _activeProfileId = loaded.activeId;
      _isLoading = false;
    });
    final cfg = _activeProfile.config;
    widget.onAppearanceChanged(cfg.themeColorValue, cfg.themeMode);
  }

  Future<void> _persistProfiles() async {
    await _storage.saveAllProfiles(
      profiles: _profiles,
      activeId: _activeProfileId,
    );
  }

  void _replaceActiveProfile(ScheduleProfile updated) {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    setState(() {
      _profiles = [..._profiles]..[idx] = updated;
    });
    widget.onAppearanceChanged(
      updated.config.themeColorValue,
      updated.config.themeMode,
    );
    _persistProfiles();
  }

  Future<void> _openCourseGroupDetail(List<Course> group) async {
    final action = await showCourseDetailSheet(
      context,
      courses: group,
      config: _activeProfile.config,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case CourseDetailEdit(:final course):
        await _openAddOrEditCourse(existing: course);
      case CourseDetailDelete(:final course):
        final updatedCourses = _activeProfile.courses
            .where((c) => c.id != course.id)
            .toList();
        _replaceActiveProfile(_activeProfile.copyWith(courses: updatedCourses));
    }
  }

  /// 周视图长按课程卡片：弹出快捷菜单（标记本周停课/恢复、编辑、删除）
  Future<void> _onLongPressCourse(Course course, int week) async {
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
                final list = _activeProfile.courses
                    .where((c) => c.id != course.id)
                    .toList();
                _replaceActiveProfile(_activeProfile.copyWith(courses: list));
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
    final result = await showCourseEditSheet(
      context,
      initialCourse: existing,
      initialWeekday: weekday,
      initialStartSection: startSection,
      totalWeeks: _activeProfile.config.totalWeeks,
      maxSections: _activeProfile.config.maxSections,
    );
    if (result == null) return;

    final currentCourses = [..._activeProfile.courses];
    if (result.deleted && existing != null) {
      currentCourses.removeWhere((c) => c.id == existing.id);
    } else if (result.course != null) {
      final idx = currentCourses.indexWhere((c) => c.id == result.course!.id);
      if (idx >= 0) {
        currentCourses[idx] = result.course!;
      } else {
        currentCourses.add(result.course!);
      }
    }
    _replaceActiveProfile(_activeProfile.copyWith(courses: currentCourses));
  }

  void _updateConfig(ScheduleConfig newConfig) {
    _replaceActiveProfile(_activeProfile.copyWith(config: newConfig));
  }

  /// 统一送入三方合并预览并应用到当前课表
  Future<void> _previewAndApplyImport(ImportPayload payload) async {
    if (!mounted) return;
    final decision = await showImportPreviewSheet(
      context,
      payload: payload,
      existingCourses: _activeProfile.courses,
    );
    if (!mounted || decision == null) return;

    final diff = ImportMergeService.computeDiff(
      _activeProfile.courses,
      payload.courses,
    );
    final mergedCourses = ImportMergeService.applyMerge(
      existing: _activeProfile.courses,
      diff: diff,
      mode: decision.mode,
      removeMissing: decision.removeMissing,
    );

    var nextConfig = _activeProfile.config;
    if (decision.applyImportedConfig && payload.hasConfigUpdates) {
      nextConfig = nextConfig.copyWith(
        semesterStart: payload.semesterStart ?? nextConfig.semesterStart,
        totalWeeks: payload.totalWeeks ?? nextConfig.totalWeeks,
        maxSections: payload.sectionTimes != null
            ? payload.sectionTimes!.length
            : nextConfig.maxSections,
        sectionTimes: payload.sectionTimes ?? nextConfig.sectionTimes,
      );
    }

    _replaceActiveProfile(
      _activeProfile.copyWith(courses: mergedCourses, config: nextConfig),
    );

    setState(() => _tabIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导入完成，当前共 ${mergedCourses.length} 门课程')),
    );
  }

  Future<void> _openWebImport() async {
    final payload = await Navigator.of(context).push<ImportPayload>(
      MaterialPageRoute(
        builder: (_) => WebImportPage(
          maxWeeks: _activeProfile.config.totalWeeks,
          maxSections: _activeProfile.config.maxSections,
        ),
      ),
    );
    if (payload != null) {
      await _previewAndApplyImport(payload);
    }
  }

  Future<void> _openAiImport() async {
    final payload = await Navigator.of(context).push<ImportPayload>(
      MaterialPageRoute(
        builder: (_) => AiImportPage(
          maxWeeks: _activeProfile.config.totalWeeks,
          maxSections: _activeProfile.config.maxSections,
        ),
      ),
    );
    if (payload != null) {
      await _previewAndApplyImport(payload);
    }
  }

  Future<void> _importFromFile() async {
    try {
      final payload = await FileImportService.pickAndParseFile(
        currentConfig: _activeProfile.config,
      );
      if (payload == null) return;
      if (!mounted) return;
      if (payload.courses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              payload.warnings.isNotEmpty
                  ? payload.warnings.first
                  : '文件中未识别到有效课程',
            ),
          ),
        );
        return;
      }
      await _previewAndApplyImport(payload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件导入失败：$e')),
      );
    }
  }

  Future<void> _exportIcsShare() async {
    if (_activeProfile.courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前课表还没有课程可导出')),
      );
      return;
    }
    try {
      final ics = FileImportService.exportIcs(
        courses: _activeProfile.courses,
        config: _activeProfile.config,
        scheduleName: _activeProfile.name,
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
    setState(() => _activeProfileId = id);
    final cfg = _activeProfile.config;
    widget.onAppearanceChanged(cfg.themeColorValue, cfg.themeMode);
    _persistProfiles();
  }

  void _createProfile(String name) {
    final created = ScheduleProfile(
      id: 'profile_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      courses: [],
      config: _activeProfile.config.copyWith(),
    );
    setState(() {
      _profiles = [..._profiles, created];
      _activeProfileId = created.id;
    });
    _persistProfiles();
  }

  void _renameActiveProfile(String name) {
    _replaceActiveProfile(_activeProfile.copyWith(name: name));
  }

  void _deleteActiveProfile() {
    if (_profiles.length <= 1) return;
    final remaining =
        _profiles.where((p) => p.id != _activeProfileId).toList();
    setState(() {
      _profiles = remaining;
      _activeProfileId = remaining.first.id;
    });
    final cfg = _activeProfile.config;
    widget.onAppearanceChanged(cfg.themeColorValue, cfg.themeMode);
    _persistProfiles();
  }

  Future<void> _importBackupJson(String jsonText) async {
    try {
      final trimmed = jsonText.trim();
      final payload = trimmed.contains('"startNode"')
          ? AiImportService.parseAiJson(
              trimmed,
              defaultMaxWeeks: _activeProfile.config.totalWeeks,
              maxSections: _activeProfile.config.maxSections,
            )
          : () {
              final imported = _storage.importBackupJson(trimmed);
              return ImportPayload(
                courses: imported.courses
                    .map((c) => c.copyWith(source: 'import'))
                    .toList(),
                sourceLabel: 'JSON 粘贴导入',
                semesterStart: imported.config?.semesterStart,
                totalWeeks: imported.config?.totalWeeks,
                sectionTimes: imported.config?.sectionTimes,
              );
            }();

      await _previewAndApplyImport(payload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON 解析失败：$e')),
      );
    }
  }

  void _loadSampleCourses() {
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

    _replaceActiveProfile(_activeProfile.copyWith(courses: samples));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已填入示例课表，切到“周课表”看看效果吧！')),
    );
  }

  void _clearAllCourses() {
    _replaceActiveProfile(_activeProfile.copyWith(courses: []));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _activeProfile;
    final pages = [
      TodayPage(
        courses: profile.courses,
        config: profile.config,
        onTapCourse: (c) => _openCourseGroupDetail([c]),
        onAddCourse: () => _openAddOrEditCourse(
          weekday: DateTime.now().weekday,
          startSection: 1,
        ),
      ),
      WeekPage(
        courses: profile.courses,
        config: profile.config,
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
        onOpenWebImport: _openWebImport,
        onOpenAiImport: _openAiImport,
        onImportFile: _importFromFile,
        onExportIcsShare: _exportIcsShare,
        onExportJson: () => _storage.exportBackupJson(
          courses: profile.courses,
          config: profile.config,
        ),
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
