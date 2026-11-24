import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/schedule_config.dart';

/// 今日课表页面（含正在上课/下一节实时状态 + 明天课表预览）
class TodayPage extends StatelessWidget {
  final List<Course> courses;
  final ScheduleConfig config;
  final ValueChanged<Course> onTapCourse;
  final VoidCallback onAddCourse;

  const TodayPage({
    super.key,
    required this.courses,
    required this.config,
    required this.onTapCourse,
    required this.onAddCourse,
  });

  static const _weekdayNames = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentWeek = config.getCurrentWeek(now);
    final todayWeekday = now.weekday;

    final todayCourses = courses
        .where(
          (c) =>
              c.weekday == todayWeekday &&
              c.isActiveInWeek(currentWeek) &&
              !c.isCanceledInWeek(currentWeek),
        )
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));

    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowWeek = config.getCurrentWeek(tomorrow);
    final tomorrowCourses = courses
        .where(
          (c) =>
              c.weekday == tomorrow.weekday &&
              c.isActiveInWeek(tomorrowWeek) &&
              !c.isCanceledInWeek(tomorrowWeek),
        )
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));

    final colorScheme = Theme.of(context).colorScheme;
    final liveStatus = _computeLiveStatus(todayCourses, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日课表'),
        actions: [
          IconButton(
            tooltip: '添加课程',
            onPressed: onAddCourse,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.secondaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
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
                            '${now.month}月${now.day}日 · ${_weekdayNames[todayWeekday - 1]}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '第 $currentWeek 周（${currentWeek.isOdd ? "单周" : "双周"}） · 今日共 ${todayCourses.length} 门课',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.today_rounded,
                      size: 38,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
                if (liveStatus != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_filled,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            liveStatus,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (todayCourses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(
                    Icons.weekend_outlined,
                    size: 56,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '今天没有课，好好休息一下吧！',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onAddCourse,
                    icon: const Icon(Icons.add),
                    label: const Text('手动添加一门课'),
                  ),
                ],
              ),
            )
          else
            ...todayCourses.map(
              (course) => _TodayCourseTile(
                course: course,
                timeRange: _formatTimeRange(course),
                isOngoing: _isOngoing(course, now),
                onTap: () => onTapCourse(course),
              ),
            ),
          if (tomorrowCourses.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '明天预览（${_weekdayNames[tomorrow.weekday - 1]} · ${tomorrowCourses.length} 门课）',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              children: tomorrowCourses
                  .map(
                    (course) => _TodayCourseTile(
                      course: course,
                      timeRange: _formatTimeRange(course),
                      isOngoing: false,
                      onTap: () => onTapCourse(course),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  String? _computeLiveStatus(List<Course> todayCourses, DateTime now) {
    if (todayCourses.isEmpty) return null;
    final nowMin = now.hour * 60 + now.minute;

    for (final c in todayCourses) {
      final range = _sectionMinutes(c);
      if (range == null) continue;
      if (nowMin >= range.start && nowMin <= range.end) {
        final remain = range.end - nowMin;
        final loc = c.location.isNotEmpty ? '（${c.location}）' : '';
        return '正在上课：${c.name}$loc · 还有 $remain 分钟下课';
      }
      if (nowMin < range.start) {
        final diff = range.start - nowMin;
        final timeHint = diff >= 60
            ? '${diff ~/ 60}小时${diff % 60}分钟后'
            : '$diff分钟后';
        final loc = c.location.isNotEmpty ? ' · ${c.location}' : '';
        return '下一节：${c.name}（$timeHint$loc）';
      }
    }
    return '今日课程已全部结束';
  }

  bool _isOngoing(Course course, DateTime now) {
    final range = _sectionMinutes(course);
    if (range == null) return false;
    final nowMin = now.hour * 60 + now.minute;
    return nowMin >= range.start && nowMin <= range.end;
  }

  ({int start, int end})? _sectionMinutes(Course course) {
    final times = config.sectionTimes;
    final sIdx = course.startSection - 1;
    final eIdx = course.endSection - 1;
    if (sIdx < 0 || eIdx >= times.length || sIdx > eIdx) return null;
    return (
      start: _parseMin(times[sIdx].start),
      end: _parseMin(times[eIdx].end),
    );
  }

  int _parseMin(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _formatTimeRange(Course course) {
    final times = config.sectionTimes;
    final startIdx = course.startSection - 1;
    final endIdx = course.endSection - 1;
    if (startIdx >= 0 && endIdx < times.length && startIdx <= endIdx) {
      return '${times[startIdx].start} - ${times[endIdx].end}';
    }
    return '第 ${course.startSection}-${course.endSection} 节';
  }
}

class _TodayCourseTile extends StatelessWidget {
  final Course course;
  final String timeRange;
  final bool isOngoing;
  final VoidCallback onTap;

  const _TodayCourseTile({
    required this.course,
    required this.timeRange,
    required this.isOngoing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Color(course.colorValue);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isOngoing
          ? accent.withValues(alpha: 0.14)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isOngoing
            ? BorderSide(color: accent, width: 1.2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 54,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            course.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isOngoing) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '上课中',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '第${course.startSection}-${course.endSection}节',
                        timeRange,
                        if (course.location.isNotEmpty) course.location,
                        if (course.teacher.isNotEmpty) course.teacher,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
