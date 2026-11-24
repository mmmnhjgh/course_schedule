/// 单节课的上下课时间段
class SectionTime {
  final String start; // 例如 '08:00'
  final String end; // 例如 '08:45'

  const SectionTime({
    required this.start,
    required this.end,
  });

  SectionTime copyWith({String? start, String? end}) {
    return SectionTime(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
    };
  }

  factory SectionTime.fromJson(Map<String, dynamic> json) {
    return SectionTime(
      start: json['start'] as String? ?? '08:00',
      end: json['end'] as String? ?? '08:45',
    );
  }
}

/// 学期与作息全局配置
class ScheduleConfig {
  final DateTime semesterStart; // 第 1 周的周一日期
  final int totalWeeks; // 本学期总周数
  final int maxSections; // 每天总节数
  final List<SectionTime> sectionTimes; // 每节课的作息时间表
  final bool showWeekend; // 是否显示周六、周日
  final int themeColorValue; // 全局主题种子颜色
  final String themeMode; // 'system' | 'light' | 'dark'

  const ScheduleConfig({
    required this.semesterStart,
    required this.totalWeeks,
    required this.maxSections,
    required this.sectionTimes,
    this.showWeekend = true,
    this.themeColorValue = 0xFF2B7FFF,
    this.themeMode = 'system',
  });

  /// 根据开学第 1 周的周一日期，计算指定日期（默认今天）属于第几周
  int getCurrentWeek([DateTime? now]) {
    final target = now ?? DateTime.now();
    // 去掉时分秒，只比较年月日，避免跨天小时差导致少算 1 天
    final todayDate = DateTime(target.year, target.month, target.day);
    final startDate = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    final diffDays = todayDate.difference(startDate).inDays;
    final week = diffDays >= 0 ? (diffDays ~/ 7) + 1 : 1;
    return week.clamp(1, totalWeeks);
  }

  /// 获取某一周周几（1~7）对应的具体日期
  DateTime dateOf(int week, int weekday) {
    final startDate = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    return startDate.add(Duration(days: (week - 1) * 7 + (weekday - 1)));
  }

  ScheduleConfig copyWith({
    DateTime? semesterStart,
    int? totalWeeks,
    int? maxSections,
    List<SectionTime>? sectionTimes,
    bool? showWeekend,
    int? themeColorValue,
    String? themeMode,
  }) {
    return ScheduleConfig(
      semesterStart: semesterStart ?? this.semesterStart,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      maxSections: maxSections ?? this.maxSections,
      sectionTimes: sectionTimes ?? this.sectionTimes,
      showWeekend: showWeekend ?? this.showWeekend,
      themeColorValue: themeColorValue ?? this.themeColorValue,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'semesterStart': semesterStart.toIso8601String(),
      'totalWeeks': totalWeeks,
      'maxSections': maxSections,
      'sectionTimes': sectionTimes.map((e) => e.toJson()).toList(),
      'showWeekend': showWeekend,
      'themeColorValue': themeColorValue,
      'themeMode': themeMode,
    };
  }

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    final rawStart = json['semesterStart'] as String?;
    final parsedStart =
        rawStart != null ? DateTime.tryParse(rawStart) : null;
    final rawTimes = json['sectionTimes'] as List<dynamic>?;

    return ScheduleConfig(
      semesterStart: parsedStart ?? _mondayOfThisWeek(),
      totalWeeks: (json['totalWeeks'] as num?)?.toInt() ?? 20,
      maxSections: (json['maxSections'] as num?)?.toInt() ?? 12,
      sectionTimes: rawTimes != null
          ? rawTimes
              .map((e) => SectionTime.fromJson(e as Map<String, dynamic>))
              .toList()
          : defaultSectionTimes(),
      showWeekend: json['showWeekend'] as bool? ?? true,
      themeColorValue:
          (json['themeColorValue'] as num?)?.toInt() ?? 0xFF2B7FFF,
      themeMode: json['themeMode'] as String? ?? 'system',
    );
  }

  /// 默认配置：以本周周一作为第 1 周、共 20 周、每天 12 节课
  factory ScheduleConfig.defaults() {
    return ScheduleConfig(
      semesterStart: _mondayOfThisWeek(),
      totalWeeks: 20,
      maxSections: 12,
      sectionTimes: defaultSectionTimes(),
    );
  }

  static DateTime _mondayOfThisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  static List<SectionTime> defaultSectionTimes() {
    return const [
      SectionTime(start: '08:00', end: '08:45'),
      SectionTime(start: '08:55', end: '09:40'),
      SectionTime(start: '10:00', end: '10:45'),
      SectionTime(start: '10:55', end: '11:40'),
      SectionTime(start: '14:00', end: '14:45'),
      SectionTime(start: '14:55', end: '15:40'),
      SectionTime(start: '16:00', end: '16:45'),
      SectionTime(start: '16:55', end: '17:40'),
      SectionTime(start: '19:00', end: '19:45'),
      SectionTime(start: '19:55', end: '20:40'),
      SectionTime(start: '20:50', end: '21:35'),
      SectionTime(start: '21:45', end: '22:30'),
    ];
  }
}
