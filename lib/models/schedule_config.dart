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

  static DateTime addCalendarDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  DateTime get firstMonday =>
      addCalendarDays(semesterStart, 1 - semesterStart.weekday);

  DateTime get endExclusive => addCalendarDays(firstMonday, totalWeeks * 7);

  int daysFromFirstMonday(DateTime date) {
    final monday = firstMonday;
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(monday.year, monday.month, monday.day)).inDays;
  }

  int? teachingWeek(DateTime date) {
    final days = daysFromFirstMonday(date);
    return days >= 0 && days < totalWeeks * 7 ? days ~/ 7 + 1 : null;
  }

  String? semesterMessage(DateTime date) {
    final days = daysFromFirstMonday(date);
    if (days < 0) return '学期未开始';
    if (days >= totalWeeks * 7) return '学期已结束';
    return null;
  }

  /// 周课表在学期外仍可从首周或末周开始浏览。
  int getCurrentWeek([DateTime? now]) {
    final days = daysFromFirstMonday(now ?? DateTime.now());
    return (days < 0 ? 1 : days ~/ 7 + 1).clamp(1, totalWeeks);
  }

  /// 获取某一周周几（1~7）对应的具体日期
  DateTime dateOf(int week, int weekday) =>
      addCalendarDays(firstMonday, (week - 1) * 7 + weekday - 1);

  static int? clockMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        hours > 23 ||
        minutes < 0 ||
        minutes > 59) {
      return null;
    }
    return hours * 60 + minutes;
  }

  ({int start, int end})? sectionMinutes(int startSection, int endSection) {
    if (startSection < 1 ||
        startSection > endSection ||
        endSection > sectionTimes.length) {
      return null;
    }
    final start = clockMinutes(sectionTimes[startSection - 1].start);
    final end = clockMinutes(sectionTimes[endSection - 1].end);
    return start != null && end != null && start < end
        ? (start: start, end: end)
        : null;
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
    return addCalendarDays(now, 1 - now.weekday);
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
