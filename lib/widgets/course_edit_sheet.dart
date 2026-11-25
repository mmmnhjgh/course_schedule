import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';

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
  List<SectionTime> sectionTimes = const [],
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
      sectionTimes: sectionTimes,
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
  final List<SectionTime> sectionTimes;

  const _CourseEditSheet({
    this.initialCourse,
    required this.initialWeekday,
    required this.initialStartSection,
    required this.totalWeeks,
    required this.maxSections,
    required this.sectionTimes,
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

  String _formatWeeksSummary() {
    if (_selectedWeeks.isEmpty) return '未选择';
    final temp = Course(
      id: '',
      name: '',
      weekday: _weekday,
      startSection: _startSection,
      sectionCount: _sectionCount,
      weeks: _selectedWeeks.toList()..sort(),
      colorValue: _colorValue,
    );
    return temp.formatWeeks();
  }

  String _formatTimePreview() {
    final endSection = _startSection + _sectionCount - 1;
    final dayLabel = _weekdayLabels[(_weekday - 1).clamp(0, 6)];
    final sectionLabel = _startSection == endSection
        ? '第 $_startSection 节'
        : '第 $_startSection-$endSection 节';

    final times = widget.sectionTimes;
    if (times.isNotEmpty &&
        _startSection - 1 < times.length &&
        endSection - 1 < times.length) {
      final startClock = times[_startSection - 1].start;
      final endClock = times[endSection - 1].end;
      return '$dayLabel $sectionLabel · $startClock - $endClock';
    }
    return '$dayLabel $sectionLabel';
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

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    IconData? icon,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 19) : null,
      filled: true,
      fillColor: colorScheme.surface,
      isDense: true,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.90;
    final maxCountForStart = widget.maxSections - _startSection + 1;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 固定顶栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color(_colorValue),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEditing ? '编辑课程' : '添加课程',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      if (_isEditing)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pop(const CourseEditResult.delete()),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 19,
                          ),
                          label: const Text(
                            '删除',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),

                // 中间可滚动表单
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. 基本信息分组
                        _buildSectionCard(
                          context,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                decoration: _fieldDecoration(
                                  context,
                                  label: '课程名称 *',
                                  hint: '例如：高等数学',
                                  icon: Icons.menu_book_outlined,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return '请输入课程名称';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _locationController,
                                      decoration: _fieldDecoration(
                                        context,
                                        label: '教室',
                                        hint: '如 教A-302',
                                        icon: Icons.location_on_outlined,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _teacherController,
                                      decoration: _fieldDecoration(
                                        context,
                                        label: '老师',
                                        hint: '选填',
                                        icon: Icons.person_outline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 2. 上课时间分组（含实时时间预览）
                        _buildSectionCard(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: _weekday,
                                      isExpanded: true,
                                      decoration: _fieldDecoration(
                                        context,
                                        label: '星期',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 12,
                                        ),
                                      ),
                                      items: List.generate(7, (i) {
                                        return DropdownMenuItem(
                                          value: i + 1,
                                          child: Text(
                                            _weekdayLabels[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _weekday = v);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: _startSection,
                                      isExpanded: true,
                                      decoration: _fieldDecoration(
                                        context,
                                        label: '开始节次',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 12,
                                        ),
                                      ),
                                      items: List.generate(
                                        widget.maxSections,
                                        (i) {
                                          final sec = i + 1;
                                          return DropdownMenuItem(
                                            value: sec,
                                            child: Text(
                                              '第 $sec 节',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        },
                                      ),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() {
                                            _startSection = v;
                                            final newMax =
                                                widget.maxSections -
                                                    _startSection +
                                                    1;
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
                                    flex: 3,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: _sectionCount,
                                      isExpanded: true,
                                      decoration: _fieldDecoration(
                                        context,
                                        label: '连上节数',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 12,
                                        ),
                                      ),
                                      items: List.generate(
                                        maxCountForStart.clamp(1, 6),
                                        (i) {
                                          final count = i + 1;
                                          return DropdownMenuItem(
                                            value: count,
                                            child: Text(
                                              '$count 节',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        },
                                      ),
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _sectionCount = v);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _formatTimePreview(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 3. 上课周次分组（5 列等宽紧凑数字网格）
                        _buildSectionCard(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '上课周次',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatWeeksSummary(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _selectedWeeks.isEmpty
                                            ? colorScheme.error
                                            : colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  _PresetChipButton(
                                    label: '全选',
                                    onTap: () => _selectWeeksPreset('all'),
                                  ),
                                  const SizedBox(width: 4),
                                  _PresetChipButton(
                                    label: '单周',
                                    onTap: () => _selectWeeksPreset('odd'),
                                  ),
                                  const SizedBox(width: 4),
                                  _PresetChipButton(
                                    label: '双周',
                                    onTap: () => _selectWeeksPreset('even'),
                                  ),
                                  const SizedBox(width: 4),
                                  _PresetChipButton(
                                    label: '清空',
                                    onTap: () => _selectWeeksPreset('clear'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _WeekGridPicker(
                                totalWeeks: widget.totalWeeks,
                                selectedWeeks: _selectedWeeks,
                                onToggle: (week) {
                                  setState(() {
                                    if (_selectedWeeks.contains(week)) {
                                      _selectedWeeks.remove(week);
                                    } else {
                                      _selectedWeeks.add(week);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 4. 卡片颜色（单行 10 色紧凑对齐）
                        _buildSectionCard(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '卡片颜色',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              _ColorPalettePicker(
                                selectedColor: _colorValue,
                                onSelect: (hex) =>
                                    setState(() => _colorValue = hex),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 5. 备注（移至次要位置）
                        _buildSectionCard(
                          context,
                          child: TextFormField(
                            controller: _noteController,
                            decoration: _fieldDecoration(
                              context,
                              label: '备注（选填）',
                              hint: '如考核方式、课程群号等',
                              icon: Icons.notes_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 吸底操作栏
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isEditing ? '保存修改' : '确认添加',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChipButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _WeekGridPicker extends StatelessWidget {
  final int totalWeeks;
  final Set<int> selectedWeeks;
  final ValueChanged<int> onToggle;

  const _WeekGridPicker({
    required this.totalWeeks,
    required this.selectedWeeks,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalWeeks,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.25,
      ),
      itemBuilder: (context, index) {
        final week = index + 1;
        final isSelected = selectedWeeks.contains(week);
        return InkWell(
          onTap: () => onToggle(week),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.primary : colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: Text(
              '$week',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ColorPalettePicker extends StatelessWidget {
  final int selectedColor;
  final ValueChanged<int> onSelect;

  const _ColorPalettePicker({
    required this.selectedColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = kCourseColorPresets.map((colorHex) {
          final isSelected = selectedColor == colorHex;
          return GestureDetector(
            onTap: () => onSelect(colorHex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Color(colorHex),
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: colorScheme.onSurface, width: 2.2)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Color(colorHex).withValues(alpha: 0.45),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 15)
                  : null,
            ),
          );
        }).toList();

        if (constraints.maxWidth >= 290) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: items,
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                items[i],
              ],
            ],
          ),
        );
      },
    );
  }
}
