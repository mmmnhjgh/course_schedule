/// 单门课程的数据模型
class Course {
  final String id;
  final String name;
  final String teacher;
  final String location;
  final String note;
  final int weekday; // 1 ~ 7（周一到周日）
  final int startSection; // 开始节次，例如 1
  final int sectionCount; // 连续几节，例如 2
  final List<int> weeks; // 上课周次，例如 [1, 2, 3, 5]
  final int colorValue; // 卡片颜色的 ARGB 整数值，例如 0xFF42A5F5
  final String source; // 'manual' | 'import'
  final bool userEdited; // 是否已被用户手动修改（智能合并时保护不被覆盖）
  final List<int> canceledWeeks; // 单周停课/请假周次

  const Course({
    required this.id,
    required this.name,
    this.teacher = '',
    this.location = '',
    this.note = '',
    required this.weekday,
    required this.startSection,
    required this.sectionCount,
    required this.weeks,
    required this.colorValue,
    this.source = 'manual',
    this.userEdited = false,
    this.canceledWeeks = const [],
  });

  /// 结束节次（例如第 1 节开始、连上 2 节，则第 2 节结束）
  int get endSection => startSection + sectionCount - 1;

  /// 用于三方合并匹配的身份键（规范化课程名 + 老师）
  String get identityKey {
    final n = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final t = teacher.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '$n|$t';
  }

  /// 判断第 [week] 周是否上这门课
  bool isActiveInWeek(int week) => weeks.contains(week);

  /// 判断第 [week] 周是否被标记为停课/请假
  bool isCanceledInWeek(int week) => canceledWeeks.contains(week);

  /// 判断两门课在星期和节次上是否重叠（忽略周次差异）
  bool overlapsSectionWith(Course other) {
    if (weekday != other.weekday) return false;
    return !(endSection < other.startSection || startSection > other.endSection);
  }

  /// 将周次列表折叠格式化为易读文本，例如 "1-16周"、"1-15周(单)"、"1-4, 6-8周"
  String formatWeeks() {
    if (weeks.isEmpty) return '未设置周次';
    final sorted = [...weeks]..sort();
    if (sorted.length == 1) return '${sorted.first}周';

    // 检测是否全是等差为 2 的连续单周或双周
    var isStepTwo = true;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] - sorted[i - 1] != 2) {
        isStepTwo = false;
        break;
      }
    }
    if (isStepTwo) {
      final suffix = sorted.first.isOdd ? '单' : '双';
      return '${sorted.first}-${sorted.last}周($suffix)';
    }

    // 折叠连续整数区间
    final segments = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      if (current == prev + 1) {
        prev = current;
      } else {
        segments.add(start == prev ? '$start' : '$start-$prev');
        start = current;
        prev = current;
      }
    }
    segments.add(start == prev ? '$start' : '$start-$prev');
    return '${segments.join(', ')}周';
  }

  /// 复制并修改部分字段（编辑课程时使用）
  Course copyWith({
    String? id,
    String? name,
    String? teacher,
    String? location,
    String? note,
    int? weekday,
    int? startSection,
    int? sectionCount,
    List<int>? weeks,
    int? colorValue,
    String? source,
    bool? userEdited,
    List<int>? canceledWeeks,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      note: note ?? this.note,
      weekday: weekday ?? this.weekday,
      startSection: startSection ?? this.startSection,
      sectionCount: sectionCount ?? this.sectionCount,
      weeks: weeks ?? this.weeks,
      colorValue: colorValue ?? this.colorValue,
      source: source ?? this.source,
      userEdited: userEdited ?? this.userEdited,
      canceledWeeks: canceledWeeks ?? this.canceledWeeks,
    );
  }

  /// 转为 JSON Map，方便本地存储与导出备份
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'teacher': teacher,
      'location': location,
      'note': note,
      'weekday': weekday,
      'startSection': startSection,
      'sectionCount': sectionCount,
      'weeks': weeks,
      'colorValue': colorValue,
      'source': source,
      'userEdited': userEdited,
      'canceledWeeks': canceledWeeks,
    };
  }

  /// 从 JSON Map 还原成 Course 对象
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      teacher: json['teacher'] as String? ?? '',
      location: json['location'] as String? ?? '',
      note: json['note'] as String? ?? '',
      weekday: (json['weekday'] as num).toInt(),
      startSection: (json['startSection'] as num).toInt(),
      sectionCount: (json['sectionCount'] as num).toInt(),
      weeks: (json['weeks'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      colorValue: (json['colorValue'] as num).toInt(),
      source: json['source'] as String? ?? 'manual',
      userEdited: json['userEdited'] as bool? ?? false,
      canceledWeeks: (json['canceledWeeks'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }
}