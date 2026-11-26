import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/course_adjustment.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import '../services/schedule_occurrences.dart';

Future<CourseAdjustment?> showCourseAdjustmentSheet(
  BuildContext context, {
  required ScheduleProfile profile,
  required DateTime date,
  Course? original,
  CourseAdjustment? existing,
}) {
  return showModalBottomSheet<CourseAdjustment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CourseAdjustmentSheet(
      profile: profile,
      date: date,
      original: original,
      existing: existing,
    ),
  );
}

class _CourseAdjustmentSheet extends StatefulWidget {
  final ScheduleProfile profile;
  final DateTime date;
  final Course? original;
  final CourseAdjustment? existing;

  const _CourseAdjustmentSheet({
    required this.profile,
    required this.date,
    this.original,
    this.existing,
  });

  @override
  State<_CourseAdjustmentSheet> createState() => _CourseAdjustmentSheetState();
}

class _CourseAdjustmentSheetState extends State<_CourseAdjustmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _location;
  late DateTime _date;
  late int _start;
  late int _end;

  ScheduleConfig get _config => widget.profile.config;
  Course? get _base => widget.existing?.course ?? widget.original;
  String? get _originalId =>
      widget.existing?.originalCourseId ?? widget.original?.id;
  DateTime? get _originalDate =>
      widget.existing?.originalDate ??
      (widget.original == null ? null : widget.date);

  @override
  void initState() {
    super.initState();
    final selected = ScheduleConfig.addCalendarDays(
      widget.existing?.date ?? widget.date,
      0,
    );
    _date = selected.isBefore(_config.firstMonday)
        ? _config.firstMonday
        : selected.isBefore(_config.endExclusive)
        ? selected
        : ScheduleConfig.addCalendarDays(_config.endExclusive, -1);
    _name = TextEditingController(text: _base?.name);
    _location = TextEditingController(text: _base?.location);
    _start = (_base?.startSection ?? 1).clamp(1, _config.maxSections);
    _end = (_base?.endSection ?? _start).clamp(_start, _config.maxSections);
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _config.firstMonday,
      lastDate: ScheduleConfig.addCalendarDays(_config.endExclusive, -1),
      helpText: '选择这次上课的日期',
    );
    if (mounted && chosen != null) setState(() => _date = chosen);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final week = _config.teachingWeek(_date)!;
    final id =
        widget.existing?.id ??
        'adjustment_${DateTime.now().microsecondsSinceEpoch}';
    final course =
        (_base ??
                const Course(
                  id: '',
                  name: '',
                  weekday: 1,
                  startSection: 1,
                  sectionCount: 1,
                  weeks: [],
                  colorValue: 0xFF2B7FFF,
                ))
            .copyWith(
              id: id,
              name: _name.text.trim(),
              location: _location.text.trim(),
              weekday: _date.weekday,
              startSection: _start,
              sectionCount: _end - _start + 1,
              weeks: [week],
              source: 'manual',
              canceledWeeks: const [],
            );
    final sameDayAsOriginal =
        _originalDate != null &&
        ScheduleConfig.dateKey(_originalDate!) == ScheduleConfig.dateKey(_date);
    final conflicts = ScheduleOccurrences(widget.profile)
        .onDate(_date)
        .map((item) => item.course)
        .where(
          (other) =>
              other.id != id &&
              !(sameDayAsOriginal && other.id == _originalId) &&
              other.overlapsSectionWith(course),
        )
        .map((other) => other.name)
        .toSet();
    if (conflicts.isNotEmpty) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('这个时段已有课程'),
          content: Text(conflicts.join('、')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保留重叠课程'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) return;
    }

    Navigator.of(context).pop(
      CourseAdjustment(
        course: course,
        date: _date,
        originalCourseId: _originalId,
        originalDate: _originalDate,
      ),
    );
  }

  Widget _sectionPicker({
    required String label,
    required int value,
    required int first,
    required ValueChanged<int> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          items: [
            for (var section = first; section <= _config.maxSections; section++)
              DropdownMenuItem(value: section, child: Text('第 $section 节')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing != null
                    ? '编辑这次安排'
                    : _originalId == null
                    ? '添加一次补课'
                    : '只调整这一次',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                readOnly: _originalId != null,
                decoration: const InputDecoration(labelText: '课程名'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入课程名' : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('上课日期'),
                subtitle: Text(ScheduleConfig.dateKey(_date)),
                onTap: _pickDate,
              ),
              Row(
                children: [
                  Expanded(
                    child: _sectionPicker(
                      label: '开始节次',
                      value: _start,
                      first: 1,
                      onChanged: (value) => setState(() {
                        _start = value;
                        if (_end < value) _end = value;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _sectionPicker(
                      label: '结束节次',
                      value: _end,
                      first: _start,
                      onChanged: (value) => setState(() => _end = value),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: '教室'),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _submit, child: const Text('保存这次安排')),
            ],
          ),
        ),
      ),
    );
  }
}
