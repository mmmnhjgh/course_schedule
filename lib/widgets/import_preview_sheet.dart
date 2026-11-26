import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_profile.dart';
import '../services/ai_import_service.dart';
import '../services/import_merge_service.dart';
import '../services/schedule_occurrences.dart';

/// 弹出三方合并预览确认窗（显示新增 / 变更 / 受保护 / 缺失，并支持选择合并模式）
Future<ScheduleProfile?> showImportPreviewSheet(
  BuildContext context, {
  required ImportPayload payload,
  required ScheduleProfile profile,
}) {
  return showModalBottomSheet<ScheduleProfile>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) =>
        _ImportPreviewSheet(payload: payload, profile: profile),
  );
}

class _ImportPreviewSheet extends StatefulWidget {
  final ImportPayload payload;
  final ScheduleProfile profile;

  const _ImportPreviewSheet({required this.payload, required this.profile});

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  late final ImportMergeDiff _initialDiff;
  final _choices = <int, int?>{};
  ImportApplyMode _mode = ImportApplyMode.smartMerge;
  bool _removeMissing = false;
  bool _applyImportedConfig = true;

  @override
  void initState() {
    super.initState();
    _initialDiff = ImportMergeService.computeDiff(
      widget.profile.courses,
      widget.payload.courses,
    );
    if (widget.profile.courses.isEmpty) {
      _mode = ImportApplyMode.replaceAll;
    }
  }

  ScheduleProfile _apply(ImportMergeDiff diff) {
    final profile = widget.profile;
    final payload = widget.payload;
    final courses = ImportMergeService.applyMerge(
      existing: profile.courses,
      diff: diff,
      mode: _mode,
      removeMissing: _removeMissing,
      reservedIds: profile.adjustments.map((item) => item.id),
    );
    final config = _applyImportedConfig
        ? profile.config.copyWith(
            semesterStart: payload.semesterStart,
            totalWeeks: payload.totalWeeks,
            maxSections: payload.sectionTimes?.length,
            sectionTimes: payload.sectionTimes,
          )
        : profile.config;
    return profile.copyWith(courses: courses, config: config);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExisting = widget.profile.courses.isNotEmpty;
    final merging = _mode == ImportApplyMode.smartMerge;
    final diff = _choices.isEmpty
        ? _initialDiff
        : ImportMergeService.computeDiff(
            widget.profile.courses,
            widget.payload.courses,
            choices: _choices,
          );
    final proposed = merging && diff.conflicts.isNotEmpty ? null : _apply(diff);
    final occurrences = proposed == null ? null : ScheduleOccurrences(proposed);
    final detached = {
      if (occurrences != null)
        for (final item in proposed!.adjustments)
          if (item.isMove && !occurrences.hasOriginal(item)) item,
    };

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
                      label: '新增 ${diff.added.length}',
                      color: Colors.green,
                    ),
                    _StatPill(
                      label: '更新 ${diff.changed.length}',
                      color: Colors.orange,
                    ),
                    _StatPill(
                      label: '保护手改 ${diff.protectedKept.length}',
                      color: Colors.blue,
                    ),
                    _StatPill(
                      label: '未变 ${diff.unchangedCount}',
                      color: Colors.grey,
                    ),
                    if (diff.removed.isNotEmpty)
                      _StatPill(
                        label: '本次未出现 ${diff.removed.length}',
                        color: Colors.red,
                      ),
                  ],
                ),
                if (diff.removed.isNotEmpty)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _removeMissing,
                    title: Text('同时移除本次未出现的 ${diff.removed.length} 门旧导入课'),
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
                children: [
                  if (detached.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('有 ${detached.length} 次调课的原安排已变动，将保留为独立补课。'),
                    ),
                  if (merging && hasExisting) ...[
                    for (final conflict in _initialDiff.conflicts)
                      _buildMatchChoice(conflict),
                    ..._buildDiffList(diff),
                  ] else
                    for (final course in widget.payload.courses)
                      _CoursePreviewTile(course: course),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: proposed == null
                    ? null
                    : () => Navigator.of(context).pop(
                        proposed.copyWith(
                          adjustments: [
                            for (final item in proposed.adjustments)
                              detached.contains(item) ? item.asMakeup() : item,
                          ],
                        ),
                      ),
                child: Text(proposed == null ? '请先确认课程配对' : '确认导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchChoice(ImportMatchConflict conflict) {
    final index = conflict.incomingIndex;
    String slot(Course course) {
      const days = ['一', '二', '三', '四', '五', '六', '日'];
      final day = course.weekday >= 1 && course.weekday <= 7
          ? '周${days[course.weekday - 1]}'
          : '星期未识别';
      return '$day 第 ${course.startSection}–${course.endSection} 节 · ${course.formatWeeks()}'
          '${course.location.isEmpty ? '' : ' · ${course.location}'}';
    }

    final taken = {
      for (final entry in _choices.entries)
        if (entry.key != index) entry.value,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${conflict.incoming.name} · ${slot(conflict.incoming)}'),
          DropdownButton<int>(
            isExpanded: true,
            value: _choices.containsKey(index) ? _choices[index] ?? -1 : null,
            hint: const Text('选择对应的旧课'),
            items: [
              for (final entry in conflict.candidates.entries)
                if (!taken.contains(entry.key))
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      '匹配旧课 · ${slot(entry.value)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              const DropdownMenuItem(value: -1, child: Text('作为新课加入，保留旧课')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _choices[index] = value == -1 ? null : value);
              }
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDiffList(ImportMergeDiff diff) {
    final items = <Widget>[];
    for (final c in diff.added) {
      items.add(
        _CoursePreviewTile(course: c, tag: '新增', tagColor: Colors.green),
      );
    }
    for (final pair in diff.changed) {
      items.add(
        _CoursePreviewTile(
          course: pair.updatedCourse,
          tag: '更新',
          tagColor: Colors.orange,
        ),
      );
    }
    for (final c in diff.protectedKept) {
      items.add(
        _CoursePreviewTile(
          course: c,
          tag: '保留手改',
          tagColor: Colors.blue,
        ),
      );
    }
    for (final c in diff.removed) {
      items.add(
        _CoursePreviewTile(
          course: c,
          tag: _removeMissing ? '将移除' : '仅旧表存在',
          tagColor: Colors.grey,
        ),
      );
    }
    if (items.isEmpty && diff.conflicts.isEmpty) {
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
