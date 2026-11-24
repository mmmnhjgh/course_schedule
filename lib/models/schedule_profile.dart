import 'course.dart';
import 'schedule_config.dart';

/// 一张完整课表档案（用于多课表/多学期切换）
class ScheduleProfile {
  final String id;
  final String name;
  final List<Course> courses;
  final ScheduleConfig config;

  const ScheduleProfile({
    required this.id,
    required this.name,
    required this.courses,
    required this.config,
  });

  ScheduleProfile copyWith({
    String? id,
    String? name,
    List<Course>? courses,
    ScheduleConfig? config,
  }) {
    return ScheduleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      courses: courses ?? this.courses,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'courses': courses.map((c) => c.toJson()).toList(),
      'config': config.toJson(),
    };
  }

  factory ScheduleProfile.fromJson(Map<String, dynamic> json) {
    final rawCourses = json['courses'] as List<dynamic>? ?? [];
    final rawConfig = json['config'] as Map<String, dynamic>?;

    return ScheduleProfile(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '默认课表',
      courses: rawCourses
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList(),
      config: rawConfig != null
          ? ScheduleConfig.fromJson(rawConfig)
          : ScheduleConfig.defaults(),
    );
  }
}
