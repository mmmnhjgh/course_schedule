import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import '../services/schedule_occurrences.dart';
import '../widgets/course_card.dart';

/// 周视图课表网格页面（支持左右滑动切周、周末隐藏、冲突角标与当前时间指示线）
class WeekPage extends StatefulWidget {
  final ScheduleProfile profile;
  final DateTime now;
  final void Function(List<Course>, DateTime) onTapCourseGroup;
  final void Function(Course course, int week)? onLongPressCourse;
  final void Function(int weekday, int startSection) onTapEmptyCell;
  final VoidCallback onImport;
  final ValueChanged<DateTime> onAddMakeup;

  ScheduleConfig get config => profile.config;

  const WeekPage({
    super.key,
    required this.profile,
    required this.now,
    required this.onTapCourseGroup,
    this.onLongPressCourse,
    required this.onTapEmptyCell,
    required this.onImport,
    required this.onAddMakeup,
  });

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  late int _selectedWeek;
  late PageController _pageController;
  bool _showNonCurrentWeek = false;

  static const double _sectionHeight = 64.0;
  static const double _timeColumnWidth = 36.0;
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _selectedWeek = widget.config.getCurrentWeek(widget.now);
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
    final previousWeek = oldWidget.config.teachingWeek(oldWidget.now);
    final currentWeek = widget.config.teachingWeek(widget.now);
    final next = previousWeek == _selectedWeek && currentWeek != null
        ? currentWeek
        : _selectedWeek.clamp(1, widget.config.totalWeeks);
    if (next != _selectedWeek) {
      _selectedWeek = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _selectedWeek == next) {
          _pageController.jumpToPage(next - 1);
        }
      });
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
    final currentWeek = widget.config.teachingWeek(widget.now);
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
                currentWeek == null ? '选择周次' : '选择周次（当前为第 $currentWeek 周）',
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
  List<List<Course>> _buildDisplayGroups(
    ScheduleOccurrences timetable,
    int week,
    int dayCount,
  ) {
    final visibleCourses = [
      for (var day = 1; day <= dayCount; day++)
        for (final occurrence in timetable.onDate(
          widget.config.dateOf(week, day),
          includeCanceled: true,
        ))
          occurrence.course,
      if (_showNonCurrentWeek)
        for (final course in widget.profile.courses)
          if (course.weekday >= 1 &&
              course.weekday <= dayCount &&
              !course.isActiveInWeek(week))
            course,
    ];

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
      final start = ScheduleConfig.clockMinutes(times[i].start);
      final end = ScheduleConfig.clockMinutes(times[i].end);
      if (start == null || end == null || end <= start) continue;
      if (nowMin < start) {
        if (i == 0) return null;
        final prevEnd = ScheduleConfig.clockMinutes(times[i - 1].end) ?? nowMin;
        final ratio = ((nowMin - prevEnd) / (start - prevEnd).clamp(1, 999))
            .clamp(0.0, 1.0);
        return i * _sectionHeight - 2 + ratio * 2;
      }
      if (nowMin < end) {
        final ratio = (nowMin - start) / (end - start).clamp(1, 999);
        return (i + ratio) * _sectionHeight;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final currentWeek = widget.config.teachingWeek(now);
    final semesterMessage = widget.config.semesterMessage(now);
    final timetable = ScheduleOccurrences(widget.profile);
    final colorScheme = Theme.of(context).colorScheme;
    final dayCount = widget.config.showWeekend ? 7 : 5;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              visualDensity: VisualDensity.compact,
              onPressed: _selectedWeek > 1
                  ? () => _jumpToWeek(_selectedWeek - 1)
                  : null,
            ),
            Flexible(
              child: InkWell(
                onTap: _pickWeek,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '第 $_selectedWeek 周',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                      Text(
                        semesterMessage ??
                            (_selectedWeek == currentWeek ? '本周' : '非本周'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              visualDensity: VisualDensity.compact,
              onPressed: _selectedWeek < widget.config.totalWeeks
                  ? () => _jumpToWeek(_selectedWeek + 1)
                  : null,
            ),
          ],
        ),
        actions: [
          if (currentWeek != null && _selectedWeek != currentWeek)
            TextButton(
              onPressed: () => _jumpToWeek(currentWeek),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
          PopupMenuButton<bool>(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onSelected: (makeup) {
              if (makeup) {
                widget.onAddMakeup(
                  _selectedWeek == currentWeek
                      ? now
                      : widget.config.dateOf(_selectedWeek, 1),
                );
              } else {
                widget.onTapEmptyCell(1, 1);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('添加课程')),
              PopupMenuItem(value: true, child: Text('添加一次补课')),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.config.totalWeeks,
        onPageChanged: (index) => setState(() => _selectedWeek = index + 1),
        itemBuilder: (context, index) {
          final week = index + 1;
          final groups = _buildDisplayGroups(timetable, week, dayCount);
          final timeLineY = week == currentWeek
              ? _currentTimeOffset(now)
              : null;

          return Column(
            children: [
              if (widget.profile.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onImport,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('导入课表'),
                  ),
                ),
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
                                        1.5;
                                    final height =
                                        primary.sectionCount * _sectionHeight -
                                            3;
                                    final left =
                                        (primary.weekday - 1) * dayWidth + 1;
                                    final width = dayWidth - 2;

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
                                        onTap: () => widget.onTapCourseGroup(
                                          group,
                                          widget.config.dateOf(
                                            week,
                                            primary.weekday,
                                          ),
                                        ),
                                        onLongPress:
                                            widget.onLongPressCourse != null
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
