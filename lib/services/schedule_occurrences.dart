import '../models/course.dart';
import '../models/course_adjustment.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';

typedef CourseOccurrence = ({
  Course course,
  DateTime date,
  CourseAdjustment? adjustment,
});

/// 应用页面、桌面同步及日历导出共用的实际排课。
class ScheduleOccurrences {
  final ScheduleProfile profile;

  ScheduleOccurrences(this.profile);

  ScheduleConfig get _config => profile.config;

  late final _validAdjustments = profile.adjustments
      .where(isValidTarget)
      .toList();
  late final _moves = {
    for (final adjustment in _validAdjustments)
      if (adjustment.isMove)
        (
          adjustment.originalCourseId!,
          ScheduleConfig.dateKey(adjustment.originalDate!),
        ),
  };
  late final _byDay = () {
    final days = <String, List<CourseAdjustment>>{};
    for (final adjustment in _validAdjustments) {
      days
          .putIfAbsent(ScheduleConfig.dateKey(adjustment.date), () => [])
          .add(adjustment);
    }
    return days;
  }();

  bool isValidTarget(CourseAdjustment adjustment) =>
      _config.teachingWeek(adjustment.date) != null &&
      adjustment.course.startSection >= 1 &&
      adjustment.course.sectionCount >= 1 &&
      adjustment.course.endSection <= _config.maxSections;

  bool hasOriginal(CourseAdjustment adjustment) {
    if (!adjustment.isMove) return false;
    final date = adjustment.originalDate!;
    final week = _config.teachingWeek(date);
    return week != null &&
        profile.courses.any(
          (course) =>
              course.id == adjustment.originalCourseId &&
              course.weekday == date.weekday &&
              course.isActiveInWeek(week) &&
              !course.isCanceledInWeek(week),
        );
  }

  List<CourseOccurrence> onDate(DateTime date, {bool includeCanceled = false}) {
    final week = _config.teachingWeek(date);
    if (week == null) return [];
    final key = ScheduleConfig.dateKey(date);
    final occurrences = <CourseOccurrence>[
      for (final course in profile.courses)
        if (course.weekday == date.weekday &&
            course.isActiveInWeek(week) &&
            (includeCanceled || !course.isCanceledInWeek(week)) &&
            !_moves.contains((course.id, key)))
          (course: course, date: date, adjustment: null),
      for (final adjustment in _byDay[key] ?? const <CourseAdjustment>[])
        (
          course: adjustment.course.copyWith(
            weekday: date.weekday,
            weeks: [week],
          ),
          date: date,
          adjustment: adjustment,
        ),
    ];
    occurrences.sort((a, b) {
      final bySection = a.course.startSection.compareTo(b.course.startSection);
      return bySection == 0
          ? a.course.name.compareTo(b.course.name)
          : bySection;
    });
    return occurrences;
  }

  Iterable<CourseOccurrence> get all sync* {
    final dates = <DateTime>{
      for (final course in profile.courses)
        if (course.weekday >= 1 && course.weekday <= 7)
          for (final week in course.weeks)
            if (week >= 1 && week <= _config.totalWeeks)
              _config.dateOf(week, course.weekday),
      for (final adjustment in _validAdjustments)
        ScheduleConfig.addCalendarDays(adjustment.date, 0),
    }.toList()..sort();
    for (final date in dates) {
      yield* onDate(date);
    }
  }
}
