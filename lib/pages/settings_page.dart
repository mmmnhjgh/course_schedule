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
  final Future<bool> Function(String widgetType) onRequestPinWidget;
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
    required this.onRequestPinWidget,
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

  void _showDesktopWidgetSheet(BuildContext context) {
    var requesting = false;
    String? requestMessage;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> requestPin(String type) async {
            if (requesting) return;
            setSheetState(() {
              requesting = true;
              requestMessage = '正在向系统桌面发送添加请求…';
            });
            final requested = await onRequestPinWidget(type);
            if (!sheetContext.mounted) return;
            setSheetState(() {
              requesting = false;
              requestMessage = requested
                  ? '已发送添加请求。请在系统弹窗中确认。若没有弹窗，可以手动添加。'
                  : '一键添加暂不可用，可以手动添加。';
            });
          }

          final theme = Theme.of(sheetContext);
          final message = requestMessage;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '添加桌面小组件',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '自动随当前课表更新，优先展示尚未下课的课程，点击卡片直达「今日」页面。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _WidgetPreviewOptionCard(
                          title: '今日课表 4×2 宽卡',
                          subtitle: '日期周次 + 最多 4 门课网格',
                          badge: '4×2',
                          onTap: requesting ? null : () => requestPin('wide'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WidgetPreviewOptionCard(
                          title: '今日课表 2×2 小卡',
                          subtitle: '当前/下节展开 + 紧接课程',
                          badge: '2×2',
                          onTap: requesting ? null : () => requestPin('compact'),
                        ),
                      ),
                    ],
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(message, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '手动添加时，长按或双指捏合桌面空白处，进入「小组件」或「插件」，找到「轻课表」。'
                    '如果进入 OPPO 或一加的「卡片中心」，将「全部卡片」滑到底，再点「插件」。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('桌面小组件'),
            subtitle: const Text('添加 4×2 今日宽卡或 2×2 今日小卡到手机桌面'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDesktopWidgetSheet(context),
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
          const _SectionTitle('示例与数据管理'),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('填入示例体验课表'),
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
          const Divider(),
          const _SectionTitle('关于与隐私'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于轻课表'),
            subtitle: const Text('v2.0.1 · 纯本地无广告课表应用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('本地隐私说明'),
            subtitle: const Text('数据仅存于本机，不收集任何个人信息'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyDialog(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    const repoUrl = 'https://github.com/mmmnhjgh/course_schedule';
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/app_icon.png',
                width: 60,
                height: 60,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.calendar_month,
                  size: 56,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '轻课表',
              style: Theme.of(dialogCtx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '版本 v2.0.1',
              style: Theme.of(dialogCtx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              '纯本地、无广告的 Flutter 安卓课表应用，支持教务网页导入、AI 转换、Excel/CSV/ICS 互通与桌面小组件。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              '包名：io.github.mmmnhjgh.courseschedule\n开源协议：MIT License',
              textAlign: TextAlign.center,
              style: Theme.of(dialogCtx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: repoUrl));
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制 GitHub 仓库地址')),
                );
              }
            },
            child: const Text('复制开源地址'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('本地隐私说明'),
        content: const Text(
          '1. 纯本地存储：您的课表数据、作息时间及配置全部保存在本机存储中，本应用不设任何云端服务器，不收集、不上传任何个人信息。\n\n'
          '2. 网络权限说明：仅在您主动使用「教务系统网页导入」打开学校教务官网登录查课时访问对应学校服务器，您的账号密码不会被本应用保存或传输至第三方。\n\n'
          '3. 零广告无追踪：本应用不含任何广告 SDK、统计埋点或后台静默联网行为。',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreviewOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback? onTap;

  const _WidgetPreviewOptionCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.add_circle_outline,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
