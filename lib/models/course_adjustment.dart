import 'course.dart';
import 'schedule_config.dart';

/// 一次调课或补课。日期以本地自然日为准。
class CourseAdjustment {
  final Course course;
  final DateTime date;
  final String? originalCourseId;
  final DateTime? originalDate;

  const CourseAdjustment({
    required this.course,
    required this.date,
    this.originalCourseId,
    this.originalDate,
  });

  String get id => course.id;
  bool get isMove => originalCourseId != null && originalDate != null;

  CourseAdjustment asMakeup() => CourseAdjustment(course: course, date: date);

  Map<String, dynamic> toJson() => {
    'course': course.toJson(),
    'date': ScheduleConfig.dateKey(date),
    if (isMove) 'originalCourseId': originalCourseId,
    if (isMove) 'originalDate': ScheduleConfig.dateKey(originalDate!),
  };

  factory CourseAdjustment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String value) {
      final date = DateTime.parse(value);
      if (ScheduleConfig.dateKey(date) != value) {
        throw const FormatException('调课日期格式不正确');
      }
      return date;
    }

    final id = json['originalCourseId'] as String?;
    final originalDate = json['originalDate'] as String?;
    if ((id == null) != (originalDate == null) || id == '') {
      throw const FormatException('调课缺少原安排');
    }
    return CourseAdjustment(
      course: Course.fromJson(json['course'] as Map<String, dynamic>),
      date: parseDate(json['date'] as String),
      originalCourseId: id,
      originalDate: originalDate == null ? null : parseDate(originalDate),
    );
  }
}
