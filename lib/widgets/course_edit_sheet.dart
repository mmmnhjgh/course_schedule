import 'package:material_ui/material_ui.dart';

import '../models/course.dart';

/// 供选择的课程卡片颜色预设
const List<int> kCourseColorPresets = [
  0xFF42A5F5, // 晴空蓝
  0xFF26A69A, // 青黛绿
  0xFF66BB6A, // 嫩草绿
  0xFFFFA726, // 暖阳橙
  0xFFEF5350, // 珊瑚红
  0xFFAB47BC, // 薰衣草紫
  0xFF5C6BC0, // 靛蓝
  0xFFEC407A, // 玫瑰粉
  0xFF8D6E63, // 焦糖棕
  0xFF78909C, // 蓝灰
];

/// 打开新增/编辑课程的底部弹窗
Future<CourseEditResult?> showCourseEditSheet(
  BuildContext context, {
  Course? initialCourse,
  int initialWeekday = 1,
  int initialStartSection = 1,
  required int totalWeeks,
  required int maxSections,
}) {
  return showModalBottomSheet<CourseEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _CourseEditSheet(
      initialCourse: initialCourse,
      initialWeekday: initialWeekday,
      initialStartSection: initialStartSection,
      totalWeeks: totalWeeks,
      maxSections: maxSections,
    ),
  );
}

/// 弹窗返回值：可能是保存的课程，也可能是请求删除
class CourseEditResult {
  final Course? course;
  final bool deleted;

  const CourseEditResult.save(this.course) : deleted = false;
  const CourseEditResult.delete()
      : course = null,
        deleted = true;
}

class _CourseEditSheet extends StatefulWidget {
  final Course? initialCourse;
  final int initialWeekday;
  final int initialStartSection;
  final int totalWeeks;
  final int maxSections;

  const _CourseEditSheet({
    this.initialCourse,
    required this.initialWeekday,
    required this.initialStartSection,
    required this.totalWeeks,
    required this.maxSections,
  });

  @override
  State<_CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<_CourseEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _teacherController;
  late final TextEditingController _noteController;

  late int _weekday;
  late int _startSection;
  late int _sectionCount;
  late Set<int> _selectedWeeks;
  late int _colorValue;

  static const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  bool get _isEditing => widget.initialCourse != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.initialCourse;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _locationController = TextEditingController(text: existing?.location ?? '');
    _teacherController = TextEditingController(text: existing?.teacher ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');

    _weekday = existing?.weekday ?? widget.initialWeekday;
    _startSection =
        (existing?.startSection ?? widget.initialStartSection)
            .clamp(1, widget.maxSections);
    final defaultCount =
        (_startSection + 1 <= widget.maxSections) ? 2 : 1;
    _sectionCount = (existing?.sectionCount ?? defaultCount)
        .clamp(1, widget.maxSections - _startSection + 1);
    _selectedWeeks = existing != null
        ? existing.weeks.toSet()
        : {for (int w = 1; w <= widget.totalWeeks; w++) w};
    _colorValue = existing?.colorValue ??
        kCourseColorPresets[_weekday % kCourseColorPresets.length];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _selectWeeksPreset(String mode) {
    setState(() {
      if (mode == 'all') {
        _selectedWeeks = {for (int w = 1; w <= widget.totalWeeks; w++) w};
      } else if (mode == 'odd') {
        _selectedWeeks = {
          for (int w = 1; w <= widget.totalWeeks; w++)
            if (w.isOdd) w,
        };
      } else if (mode == 'even') {
        _selectedWeeks = {
          for (int w = 1; w <= widget.totalWeeks; w++)
            if (w.isEven) w,
        };
      } else {
        _selectedWeeks.clear();
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWeeks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个上课周次')),
      );
      return;
    }

    final sortedWeeks = _selectedWeeks.toList()..sort();
    final existing = widget.initialCourse;
    final course = Course(
      id: existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      teacher: _teacherController.text.trim(),
      location: _locationController.text.trim(),
      note: _noteController.text.trim(),
      weekday: _weekday,
      startSection: _startSection,
      sectionCount: _sectionCount,
      weeks: sortedWeeks,
      colorValue: _colorValue,
      source: existing?.source ?? 'manual',
      userEdited: existing != null && existing.source == 'import'
          ? true
          : (existing?.userEdited ?? false),
      canceledWeeks: existing?.canceledWeeks ?? const [],
    );
    Navigator.of(context).pop(CourseEditResult.save(course));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxCountForStart = widget.maxSections - _startSection + 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    _isEditing ? '编辑课程' : '添加课程',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pop(const CourseEditResult.delete()),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        '删除',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '课程名称 *',
                  hintText: '例如：高等数学',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入课程名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: '教室',
                        hintText: '如 教A-302',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _teacherController,
                      decoration: const InputDecoration(
                        labelText: '老师',
                        hintText: '选填',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '如考核方式、课程群号等（选填）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _weekday,
                      decoration: const InputDecoration(
                        labelText: '星期',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(7, (i) {
                        return DropdownMenuItem(
                          value: i + 1,
                          child: Text(_weekdayLabels[i]),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) setState(() => _weekday = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startSection,
                      decoration: const InputDecoration(
                        labelText: '开始节次',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(widget.maxSections, (i) {
                        final sec = i + 1;
                        return DropdownMenuItem(
                          value: sec,
                          child: Text('第 $sec 节'),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _startSection = v;
                            final newMax = widget.maxSections - _startSection + 1;
                            if (_sectionCount > newMax) {
                              _sectionCount = newMax;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _sectionCount,
                      decoration: const InputDecoration(
                        labelText: '连上节数',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(maxCountForStart.clamp(1, 6), (i) {
                        final count = i + 1;
                        return DropdownMenuItem(
                          value: count,
                          child: Text('$count 节'),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) setState(() => _sectionCount = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '上课周次',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _selectWeeksPreset('all'),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => _selectWeeksPreset('odd'),
                    child: const Text('单周'),
                  ),
                  TextButton(
                    onPressed: () => _selectWeeksPreset('even'),
                    child: const Text('双周'),
                  ),
                  TextButton(
                    onPressed: () => _selectWeeksPreset('clear'),
                    child: const Text('清空'),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(widget.totalWeeks, (i) {
                  final week = i + 1;
                  final selected = _selectedWeeks.contains(week);
                  return FilterChip(
                    label: Text('$week'),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (isOn) {
                      setState(() {
                        if (isOn) {
                          _selectedWeeks.add(week);
                        } else {
                          _selectedWeeks.remove(week);
                        }
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text(
                '卡片颜色',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kCourseColorPresets.map((colorHex) {
                  final isSelected = _colorValue == colorHex;
                  return GestureDetector(
                    onTap: () => setState(() => _colorValue = colorHex),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(colorHex),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.black87, width: 2.5)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(_isEditing ? '保存修改' : '确认添加'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
