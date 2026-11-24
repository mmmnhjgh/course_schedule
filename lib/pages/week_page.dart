import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../widgets/course_card.dart';

/// 周视图课表网格页面（支持左右滑动切周、周末隐藏、冲突角标与当前时间指示线）
class WeekPage extends StatefulWidget {
  final List<Course> courses;
  final ScheduleConfig config;
  final ValueChanged<List<Course>> onTapCourseGroup;
  final void Function(Course course, int week)? onLongPressCourse;
  final void Function(int weekday, int startSection) onTapEmptyCell;

  const WeekPage({
    super.key,
    required this.courses,
    required this.config,
    required this.onTapCourseGroup,
    this.onLongPressCourse,
    required this.onTapEmptyCell,
  });

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  late int _selectedWeek;
  late PageController _pageController;
  bool _showNonCurrentWeek = false;

  static const double _sectionHeight = 62.0;
  static const double _timeColumnWidth = 44.0;
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _selectedWeek = widget.config.getCurrentWeek();
    _pageController = PageController(initialPage: _selectedWeek - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WeekPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedWeek > widget.config.totalWeeks) {
      _selectedWeek = widget.config.totalWeeks;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedWeek - 1);
      }
    }
  }

  void _jumpToWeek(int week) {
    final clamped = week.clamp(1, widget.config.totalWeeks);
    setState(() => _selectedWeek = clamped);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        clamped - 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _pickWeek() {
    final currentWeek = widget.config.getCurrentWeek();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择周次（当前为第 $currentWeek 周）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(widget.config.totalWeeks, (i) {
                  final week = i + 1;
                  final isSelected = week == _selectedWeek;
                  final isNow = week == currentWeek;
                  return ChoiceChip(
                    label: Text(isNow ? '$week(本周)' : '$week'),
                    selected: isSelected,
                    onSelected: (_) {
                      Navigator.of(context).pop();
                      _jumpToWeek(week);
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 将某一周需要展示的课程按重叠时段分组（每组首元素为最优先展示的课程）
  List<List<Course>> _buildDisplayGroups(int week, int dayCount) {
    final visibleCourses = widget.courses.where((c) {
      if (c.weekday < 1 || c.weekday > dayCount) return false;
      return _showNonCurrentWeek || c.isActiveInWeek(week);
    }).toList();

    // 本周课程优先于非本周课程，同优先级按开始节次排序
    visibleCourses.sort((a, b) {
      final aActive = a.isActiveInWeek(week) ? 0 : 1;
      final bActive = b.isActiveInWeek(week) ? 0 : 1;
      if (aActive != bActive) return aActive.compareTo(bActive);
      return a.startSection.compareTo(b.startSection);
    });

    final groups = <List<Course>>[];
    for (final course in visibleCourses) {
      var placed = false;
      for (final group in groups) {
        if (group.any((member) => member.overlapsSectionWith(course))) {
          group.add(course);
          placed = true;
          break;
        }
      }
      if (!placed) {
        groups.add([course]);
      }
    }
    return groups;
  }

  /// 计算当前时刻在周课表中的垂直像素偏移（仅用于本周红线提示）
  double? _currentTimeOffset(DateTime now) {
    final times = widget.config.sectionTimes;
    final maxSec = widget.config.maxSections;
    if (times.isEmpty) return null;

    final nowMin = now.hour * 60 + now.minute;
    for (var i = 0; i < maxSec && i < times.length; i++) {
      final start = _toMinutes(times[i].start);
      final end = _toMinutes(times[i].end);
      if (nowMin < start) {
        if (i == 0) return null;
        final prevEnd = _toMinutes(times[i - 1].end);
        final ratio = ((nowMin - prevEnd) / (start - prevEnd).clamp(1, 999))
            .clamp(0.0, 1.0);
        return i * _sectionHeight - 2 + ratio * 2;
      }
      if (nowMin <= end) {
        final ratio = (nowMin - start) / (end - start).clamp(1, 999);
        return (i + ratio) * _sectionHeight;
      }
    }
    return null;
  }

  int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final currentWeek = widget.config.getCurrentWeek();
    final now = DateTime.now();
    final colorScheme = Theme.of(context).colorScheme;
    final dayCount = widget.config.showWeekend ? 7 : 5;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _selectedWeek > 1
                  ? () => _jumpToWeek(_selectedWeek - 1)
                  : null,
            ),
            InkWell(
              onTap: _pickWeek,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '第 $_selectedWeek 周',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 20),
                      ],
                    ),
                    Text(
                      _selectedWeek == currentWeek ? '本周' : '非本周（点此切回）',
                      style: TextStyle(
                        fontSize: 11,
                        color: _selectedWeek == currentWeek
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _selectedWeek < widget.config.totalWeeks
                  ? () => _jumpToWeek(_selectedWeek + 1)
                  : null,
            ),
          ],
        ),
        actions: [
          if (_selectedWeek != currentWeek)
            TextButton(
              onPressed: () => _jumpToWeek(currentWeek),
              child: const Text('回本周'),
            ),
          IconButton(
            tooltip: _showNonCurrentWeek ? '隐藏非本周课程' : '显示非本周课程',
            icon: Icon(
              _showNonCurrentWeek
                  ? Icons.visibility
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () =>
                setState(() => _showNonCurrentWeek = !_showNonCurrentWeek),
          ),
          IconButton(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onPressed: () => widget.onTapEmptyCell(1, 1),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.config.totalWeeks,
        onPageChanged: (index) => setState(() => _selectedWeek = index + 1),
        itemBuilder: (context, index) {
          final week = index + 1;
          final groups = _buildDisplayGroups(week, dayCount);
          final timeLineY =
              week == currentWeek ? _currentTimeOffset(now) : null;

          return Column(
            children: [
              _buildWeekdayHeader(context, week, dayCount, now),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: widget.config.maxSections * _sectionHeight,
                    child: Row(
                      children: [
                        _buildSectionTimeColumn(context),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final dayWidth = constraints.maxWidth / dayCount;
                              return Stack(
                                children: [
                                  _buildBackgroundGrid(dayWidth, dayCount),
                                  ...groups.map((group) {
                                    final primary = group.first;
                                    final top = (primary.startSection - 1) *
                                            _sectionHeight +
                                        2;
                                    final height =
                                        primary.sectionCount * _sectionHeight -
                                            4;
                                    final left =
                                        (primary.weekday - 1) * dayWidth + 2;
                                    final width = dayWidth - 4;

                                    return Positioned(
                                      top: top,
                                      left: left,
                                      width: width,
                                      height: height,
                                      child: CourseCard(
                                        course: primary,
                                        isCurrentWeek:
                                            primary.isActiveInWeek(week),
                                        isCanceled:
                                            primary.isCanceledInWeek(week),
                                        conflictCount: group.length - 1,
                                        onTap: () =>
                                            widget.onTapCourseGroup(group),
                                        onLongPress: widget.onLongPressCourse !=
                                                null
                                            ? () => widget.onLongPressCourse!(
                                                  primary,
                                                  week,
                                                )
                                            : null,
                                      ),
                                    );
                                  }),
                                  if (timeLineY != null)
                                    Positioned(
                                      top: timeLineY,
                                      left: 0,
                                      right: 0,
                                      child: IgnorePointer(
                                        child: Container(
                                          height: 1.5,
                                          color: Colors.redAccent
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWeekdayHeader(
    BuildContext context,
    int week,
    int dayCount,
    DateTime now,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final monday = widget.config.dateOf(week, 1);

    return Container(
      color: colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Center(
              child: Text(
                '${monday.month}月',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          ...List.generate(dayCount, (i) {
            final date = widget.config.dateOf(week, i + 1);
            final isToday = date.year == now.year &&
                date.month == now.month &&
                date.day == now.day;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: isToday
                    ? BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Column(
                  children: [
                    Text(
                      '周${_weekdayLabels[i]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.w500,
                        color: isToday ? colorScheme.primary : null,
                      ),
                    ),
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isToday
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSectionTimeColumn(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _timeColumnWidth,
      child: Column(
        children: List.generate(widget.config.maxSections, (i) {
          final sectionNum = i + 1;
          final time = i < widget.config.sectionTimes.length
              ? widget.config.sectionTimes[i].start
              : '';
          return Container(
            height: _sectionHeight,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 0.5,
                ),
                right: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$sectionNum',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBackgroundGrid(double dayWidth, int dayCount) {
    final gridLineColor =
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35);

    return Column(
      children: List.generate(widget.config.maxSections, (row) {
        return SizedBox(
          height: _sectionHeight,
          child: Row(
            children: List.generate(dayCount, (col) {
              return SizedBox(
                width: dayWidth,
                height: _sectionHeight,
                child: InkWell(
                  onTap: () => widget.onTapEmptyCell(col + 1, row + 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: gridLineColor, width: 0.5),
                        right: BorderSide(color: gridLineColor, width: 0.5),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}
