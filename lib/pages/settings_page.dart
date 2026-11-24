import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import '../widgets/course_edit_sheet.dart';
import 'section_times_page.dart';

/// 设置与多源导入页面（支持多课表档案、作息配置、WebView/AI/文件导入与 ICS/JSON 分享）
class SettingsPage extends StatelessWidget {
  final List<ScheduleProfile> profiles;
  final ScheduleProfile activeProfile;
  final ValueChanged<String> onSwitchProfile;
  final ValueChanged<String> onCreateProfile;
  final ValueChanged<String> onRenameActiveProfile;
  final VoidCallback onDeleteActiveProfile;
  final ValueChanged<ScheduleConfig> onUpdateConfig;
  final VoidCallback onOpenWebImport;
  final VoidCallback onOpenAiImport;
  final VoidCallback onImportFile;
  final VoidCallback onExportIcsShare;
  final String Function() onExportJson;
  final void Function(String jsonText) onImportJson;
  final VoidCallback onLoadSampleCourses;
  final VoidCallback onClearAllCourses;

  const SettingsPage({
    super.key,
    required this.profiles,
    required this.activeProfile,
    required this.onSwitchProfile,
    required this.onCreateProfile,
    required this.onRenameActiveProfile,
    required this.onDeleteActiveProfile,
    required this.onUpdateConfig,
    required this.onOpenWebImport,
    required this.onOpenAiImport,
    required this.onImportFile,
    required this.onExportIcsShare,
    required this.onExportJson,
    required this.onImportJson,
    required this.onLoadSampleCourses,
    required this.onClearAllCourses,
  });

  ScheduleConfig get _config => activeProfile.config;
  List<Course> get _courses => activeProfile.courses;

  Future<void> _pickSemesterStart(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.semesterStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择第 1 周的周一日期',
    );
    if (picked == null) return;

    final monday = picked.subtract(Duration(days: picked.weekday - 1));
    onUpdateConfig(_config.copyWith(semesterStart: monday));
  }

  Future<void> _pickTotalWeeks(BuildContext context) async {
    int tempWeeks = _config.totalWeeks;
    final confirmed = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设置学期总周数'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: tempWeeks > 10
                    ? () => setDialogState(() => tempWeeks--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '$tempWeeks 周',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: tempWeeks < 30
                    ? () => setDialogState(() => tempWeeks++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(tempWeeks),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != null) {
      onUpdateConfig(_config.copyWith(totalWeeks: confirmed));
    }
  }

  Future<void> _openSectionTimes(BuildContext context) async {
    final updated = await Navigator.of(context).push<ScheduleConfig>(
      MaterialPageRoute(
        builder: (_) => SectionTimesPage(config: _config),
      ),
    );
    if (updated != null) {
      onUpdateConfig(updated);
    }
  }

  void _showProfilesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '切换或管理课表',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _promptProfileName(
                      context,
                      title: '新建课表',
                      initial: '新学期课表',
                      onConfirm: onCreateProfile,
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...profiles.map((p) {
              final isCurrent = p.id == activeProfile.id;
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.check_circle : Icons.table_chart_outlined,
                  color: isCurrent
                      ? Theme.of(sheetContext).colorScheme.primary
                      : null,
                ),
                title: Text(p.name),
                subtitle: Text('${p.courses.length} 门课程'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (!isCurrent) onSwitchProfile(p.id);
                },
                trailing: isCurrent
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '重命名',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _promptProfileName(
                                context,
                                title: '重命名当前课表',
                                initial: p.name,
                                onConfirm: onRenameActiveProfile,
                              );
                            },
                          ),
                          if (profiles.length > 1)
                            IconButton(
                              tooltip: '删除当前课表',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                onDeleteActiveProfile();
                              },
                            ),
                        ],
                      )
                    : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  void _promptProfileName(
    BuildContext context, {
    required String title,
    required String initial,
    required ValueChanged<String> onConfirm,
  }) {
    final controller = TextEditingController(text: initial);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：2026秋主修课表',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop();
              onConfirm(name);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAppearanceDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主题与深色模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('深色模式'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('跟随系统')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'dark', label: Text('深色')),
              ],
              selected: {_config.themeMode},
              onSelectionChanged: (selected) {
                Navigator.of(context).pop();
                onUpdateConfig(_config.copyWith(themeMode: selected.first));
              },
            ),
            const SizedBox(height: 16),
            const Text('主题强调色'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kCourseColorPresets.map((hex) {
                final selected = _config.themeColorValue == hex;
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onUpdateConfig(_config.copyWith(themeColorValue: hex));
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(hex),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.black87, width: 2.5)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final jsonText = onExportJson();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出 JSON 备份'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonText,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制课表备份 JSON 到剪贴板')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制全部'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 JSON 文本导入恢复'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '粘贴之前导出的 JSON 文本...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(context).pop();
              onImportJson(text);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = _config.semesterStart;
    final dateStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    final themeLabel = switch (_config.themeMode) {
      'light' => '浅色模式',
      'dark' => '深色模式',
      _ => '跟随系统',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('设置与导入')),
      body: ListView(
        children: [
          const _SectionTitle('多课表与学期设置'),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('当前课表档案'),
            subtitle: Text('${activeProfile.name}（共 ${profiles.length} 张）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showProfilesSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('第 1 周周一日期'),
            subtitle: Text('$dateStr（当前第 ${_config.getCurrentWeek()} 周）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickSemesterStart(context),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('学期总周数'),
            subtitle: Text('共 ${_config.totalWeeks} 周'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTotalWeeks(context),
          ),
          ListTile(
            leading: const Icon(Icons.access_time_outlined),
            title: const Text('作息时间与每天节数'),
            subtitle: Text('每天 ${_config.maxSections} 节'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSectionTimes(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.weekend_outlined),
            title: const Text('周课表显示周六、周日'),
            subtitle: const Text('关闭后仅展示周一至周五，格子更宽'),
            value: _config.showWeekend,
            onChanged: (v) => onUpdateConfig(_config.copyWith(showWeekend: v)),
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Color(_config.themeColorValue),
            ),
            title: const Text('主题色与深色模式'),
            subtitle: Text(themeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAppearanceDialog(context),
          ),
          const Divider(),
          const _SectionTitle('多源导入与分享'),
          ListTile(
            leading: const Icon(Icons.public_outlined),
            title: const Text('教务系统网页导入（WebView）'),
            subtitle: const Text('支持全国高校检索、正方/强智专抓与通用表格'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenWebImport,
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI 一键转换导入'),
            subtitle: const Text('复制提示词给任意 AI，文字/截图直接转课表'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenAiImport,
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('从文件导入（Excel / CSV / ICS / JSON）'),
            subtitle: const Text('支持教务导出表格与 .ics 日历分享文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onImportFile,
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('分享 / 导出为 .ics 日历文件'),
            subtitle: Text('当前课表共 ${_courses.length} 门课程，可发微信或导入系统日历'),
            onTap: onExportIcsShare,
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('复制 / 导出 JSON 备份'),
            onTap: () => _showExportDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('粘贴 JSON 文本导入'),
            onTap: () => _showImportDialog(context),
          ),
          const Divider(),
          const _SectionTitle('调试与体验'),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('填入示例测试课表'),
            subtitle: const Text('快速预览单双周、连续多节课与冲突效果'),
            onTap: onLoadSampleCourses,
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            title: const Text('清空当前课表课程', style: TextStyle(color: Colors.red)),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认清空？'),
                  content: const Text('清空后当前课表内的课程将被删除，建议先导出备份。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onClearAllCourses();
                      },
                      child: const Text('确认清空'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
