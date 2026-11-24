import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/ai_import_service.dart';
import '../services/import_merge_service.dart';

/// 统一导入预览结果
class ImportPreviewDecision {
  final ImportApplyMode mode;
  final bool removeMissing;
  final bool applyImportedConfig;

  const ImportPreviewDecision({
    required this.mode,
    required this.removeMissing,
    required this.applyImportedConfig,
  });
}

/// 弹出三方合并预览确认窗（显示新增 / 变更 / 受保护 / 缺失，并支持选择合并模式）
Future<ImportPreviewDecision?> showImportPreviewSheet(
  BuildContext context, {
  required ImportPayload payload,
  required List<Course> existingCourses,
}) {
  return showModalBottomSheet<ImportPreviewDecision>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ImportPreviewSheet(
      payload: payload,
      existingCourses: existingCourses,
    ),
  );
}

class _ImportPreviewSheet extends StatefulWidget {
  final ImportPayload payload;
  final List<Course> existingCourses;

  const _ImportPreviewSheet({
    required this.payload,
    required this.existingCourses,
  });

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  late final ImportMergeDiff _diff;
  ImportApplyMode _mode = ImportApplyMode.smartMerge;
  bool _removeMissing = false;
  bool _applyImportedConfig = true;

  @override
  void initState() {
    super.initState();
    _diff = ImportMergeService.computeDiff(
      widget.existingCourses,
      widget.payload.courses,
    );
    // 如果当前还没有任何课程，默认直接导入即可
    if (widget.existingCourses.isEmpty) {
      _mode = ImportApplyMode.replaceAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExisting = widget.existingCourses.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '识别到 ${widget.payload.courses.length} 门课程',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (widget.payload.sourceLabel.isNotEmpty)
                        Text(
                          '来源：${widget.payload.sourceLabel}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasExisting) ...[
              SegmentedButton<ImportApplyMode>(
                segments: const [
                  ButtonSegment(
                    value: ImportApplyMode.smartMerge,
                    label: Text('智能合并'),
                  ),
                  ButtonSegment(
                    value: ImportApplyMode.replaceAll,
                    label: Text('覆盖课表'),
                  ),
                  ButtonSegment(
                    value: ImportApplyMode.appendAll,
                    label: Text('追加'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (sel) => setState(() => _mode = sel.first),
              ),
              const SizedBox(height: 8),
              if (_mode == ImportApplyMode.smartMerge) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _StatPill(
                      label: '新增 ${_diff.added.length}',
                      color: Colors.green,
                    ),
                    _StatPill(
                      label: '更新 ${_diff.changed.length}',
                      color: Colors.orange,
                    ),
                    _StatPill(
                      label: '保护手改 ${_diff.protectedKept.length}',
                      color: Colors.blue,
                    ),
                    _StatPill(
                      label: '未变 ${_diff.unchangedCount}',
                      color: Colors.grey,
                    ),
                    if (_diff.removed.isNotEmpty)
                      _StatPill(
                        label: '本次未出现 ${_diff.removed.length}',
                        color: Colors.red,
                      ),
                  ],
                ),
                if (_diff.removed.isNotEmpty)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _removeMissing,
                    title: Text('同时移除本次未出现的 ${_diff.removed.length} 门旧导入课'),
                    onChanged: (v) =>
                        setState(() => _removeMissing = v ?? false),
                  ),
              ],
            ],
            if (widget.payload.hasConfigUpdates)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _applyImportedConfig,
                title: const Text('同步更新导入自带的开学日期 / 总周数 / 作息时间'),
                onChanged: (v) =>
                    setState(() => _applyImportedConfig = v ?? true),
              ),
            if (widget.payload.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '提示：${widget.payload.warnings.first}'
                  '${widget.payload.warnings.length > 1 ? " 等 ${widget.payload.warnings.length} 条" : ""}',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: _mode == ImportApplyMode.smartMerge && hasExisting
                    ? _buildDiffList(context)
                    : widget.payload.courses
                        .map((c) => _CoursePreviewTile(course: c))
                        .toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  ImportPreviewDecision(
                    mode: _mode,
                    removeMissing: _removeMissing,
                    applyImportedConfig: _applyImportedConfig,
                  ),
                ),
                child: const Text('确认导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDiffList(BuildContext context) {
    final items = <Widget>[];
    for (final c in _diff.added) {
      items.add(_CoursePreviewTile(course: c, tag: '新增', tagColor: Colors.green));
    }
    for (final pair in _diff.changed) {
      items.add(
        _CoursePreviewTile(
          course: pair.updatedCourse,
          tag: '更新',
          tagColor: Colors.orange,
        ),
      );
    }
    for (final c in _diff.protectedKept) {
      items.add(
        _CoursePreviewTile(
          course: c,
          tag: '保留手改',
          tagColor: Colors.blue,
        ),
      );
    }
    for (final c in _diff.removed) {
      items.add(
        _CoursePreviewTile(
          course: c,
          tag: _removeMissing ? '将移除' : '仅旧表存在',
          tagColor: Colors.grey,
        ),
      );
    }
    if (items.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('所有课程均与当前课表一致，无需额外改动')),
        ),
      );
    }
    return items;
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CoursePreviewTile extends StatelessWidget {
  final Course course;
  final String? tag;
  final Color? tagColor;

  const _CoursePreviewTile({
    required this.course,
    this.tag,
    this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 10,
        backgroundColor: Color(course.colorValue),
      ),
      title: Text(course.name),
      subtitle: Text(
        '周${course.weekday} 第${course.startSection}-${course.endSection}节 · ${course.formatWeeks()}'
        '${course.location.isNotEmpty ? " · ${course.location}" : ""}',
      ),
      trailing: tag != null
          ? _StatPill(label: tag!, color: tagColor ?? Colors.grey)
          : null,
    );
  }
}
