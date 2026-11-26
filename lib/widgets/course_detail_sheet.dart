import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';

/// 点击课程卡片后返回的交互动作
sealed class CourseDetailAction {
  const CourseDetailAction();
}

class CourseDetailEdit extends CourseDetailAction {
  final Course course;
  const CourseDetailEdit(this.course);
}

class CourseDetailDelete extends CourseDetailAction {
  final Course course;
  const CourseDetailDelete(this.course);
}

class CourseDetailAdjust extends CourseDetailAction {
  final Course course;
  const CourseDetailAdjust(this.course);
}

/// 打开课程详情弹窗（支持同一时段有多门冲突课程时切换查看）
Future<CourseDetailAction?> showCourseDetailSheet(
  BuildContext context, {
  required List<Course> courses,
  required ScheduleConfig config,
  bool Function(Course)? canAdjust,
  String? Function(Course)? adjustmentLabel,
}) {
  return showModalBottomSheet<CourseDetailAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CourseDetailSheet(
      courses: courses,
      config: config,
      canAdjust: canAdjust,
      adjustmentLabel: adjustmentLabel,
    ),
  );
}

class _CourseDetailSheet extends StatefulWidget {
  final List<Course> courses;
  final ScheduleConfig config;
  final bool Function(Course)? canAdjust;
  final String? Function(Course)? adjustmentLabel;

  const _CourseDetailSheet({
    required this.courses,
    required this.config,
    this.canAdjust,
    this.adjustmentLabel,
  });

  @override
  State<_CourseDetailSheet> createState() => _CourseDetailSheetState();
}

class _CourseDetailSheetState extends State<_CourseDetailSheet> {
  int _selectedIdx = 0;

  static const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String _formatTimeRange(Course c) {
    final times = widget.config.sectionTimes;
    final startIdx = c.startSection - 1;
    final endIdx = c.endSection - 1;
    if (startIdx >= 0 && endIdx < times.length && startIdx <= endIdx) {
      return '${times[startIdx].start} - ${times[endIdx].end}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.courses[_selectedIdx];
    final accent = Color(course.colorValue);
    final timeStr = _formatTimeRange(course);
    final adjustment = widget.adjustmentLabel?.call(course);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.courses.length > 1) ...[
            Text(
              '该时段共有 ${widget.courses.length} 门重叠课程（点击切换）：',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.courses.length, (i) {
                  final item = widget.courses[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item.name),
                      selected: i == _selectedIdx,
                      onSelected: (_) => setState(() => _selectedIdx = i),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                width: 12,
                height: 28,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  course.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.schedule,
            label: '时间',
            value:
                '${_weekdayNames[course.weekday - 1]} 第${course.startSection}-${course.endSection}节'
                '${timeStr.isNotEmpty ? "（$timeStr）" : ""}',
          ),
          _DetailRow(
            icon: Icons.date_range_outlined,
            label: '周次',
            value: course.formatWeeks(),
          ),
          if (course.location.isNotEmpty)
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: '教室',
              value: course.location,
            ),
          if (course.teacher.isNotEmpty)
            _DetailRow(
              icon: Icons.person_outline,
              label: '老师',
              value: course.teacher,
            ),
          if (course.note.isNotEmpty)
            _DetailRow(
              icon: Icons.notes_outlined,
              label: '备注',
              value: course.note,
            ),
          const SizedBox(height: 20),
          if (widget.canAdjust?.call(course) == true)
            TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(CourseDetailAdjust(course)),
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('只调整这一次'),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(CourseDetailDelete(course)),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    adjustment == '调课'
                        ? '撤销调课'
                        : adjustment == '补课'
                        ? '删除补课'
                        : '删除',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(CourseDetailEdit(course)),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(adjustment == null ? '编辑课程' : '编辑本次$adjustment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
