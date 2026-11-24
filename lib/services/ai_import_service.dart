import 'dart:convert';

import '../models/course.dart';
import '../models/schedule_config.dart';
import 'edu_parsers.dart';

/// 通用导入载荷（供 WebView、AI 转换、Excel/CSV/ICS 统一送入合并预览）
class ImportPayload {
  final List<Course> courses;
  final List<String> warnings;
  final String sourceLabel;
  final DateTime? semesterStart;
  final int? totalWeeks;
  final List<SectionTime>? sectionTimes;

  const ImportPayload({
    required this.courses,
    this.warnings = const [],
    this.sourceLabel = '',
    this.semesterStart,
    this.totalWeeks,
    this.sectionTimes,
  });

  bool get hasConfigUpdates =>
      semesterStart != null || totalWeeks != null || sectionTimes != null;
}

/// AI 一键转换服务：提供 Prompt 模板并容错解析 AI 返回的 JSON
class AiImportService {
  static const String aiPrompt = '''你是课表数据转换器。我会给你一份课表（文字、截图或表格），请把它转换成下面这种 JSON。

## 输出格式
{
  "tableName": "课表名称",
  "startDate": "YYYY-MM-DD",
  "totalWeeks": 20,
  "timeSlots": [
    { "node": 1, "startTime": "08:00", "endTime": "08:45" }
  ],
  "courses": [
    {
      "name": "课程名",
      "day": 1,
      "startNode": 1,
      "step": 2,
      "weeks": [1, 2, 3],
      "teacher": "教师",
      "location": "地点",
      "note": "备注"
    }
  ]
}

## 字段规则
- day：星期，周一=1 … 周日=7，整数。
- startNode：起始节次；step：连续节数。例如第 3–4 节 → startNode 3，step 2。
- weeks：列出每一个上课周的整数数组，不要写区间字符串。"3-5周,7-11周" → [3,4,5,7,8,9,10,11]；"1-16周单周" → [1,3,5,...,15]；"双周"同理。
- 同一门课在不同时间段或不同周次上课，拆成多条 courses 记录，name 保持一致。
- 一个格子里有多门课，每门课各一条记录。
- teacher、location、note 不存在时省略该字段，不要写 null。
- timeSlots：课表上有节次时间就完整列出，node 从 1 连续编号；没有就省略 timeSlots。
- startDate：第 1 周周一日期；没有就省略。totalWeeks：总周数；没有就省略。
- 只转换有明确星期和节次的课程；没有具体时间的课程（如实践周、讲座）忽略。

## 输出要求
- 只输出一个合法 JSON 对象，不要解释和注释。
- 课程名、教师、地点保留原文，不翻译、不缩写。

下面是课表：
''';

  /// 解析 AI 输出文本（自动剥离 ```json 代码块与前后多余文字）
  static ImportPayload parseAiJson(
    String rawText, {
    int defaultMaxWeeks = 20,
    int maxSections = 14,
  }) {
    final cleaned = _extractJsonString(rawText);
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 返回内容不是 JSON 对象（需要包含 courses 数组）');
    }

    final rawCourses = decoded['courses'];
    if (rawCourses is! List<dynamic>) {
      throw const FormatException('JSON 缺少 courses 数组');
    }

    final totalWeeksRaw = (decoded['totalWeeks'] as num?)?.toInt();
    final effectiveMaxWeeks =
        (totalWeeksRaw != null && totalWeeksRaw >= 1 && totalWeeksRaw <= 40)
            ? totalWeeksRaw
            : defaultMaxWeeks;

    final startDateRaw = decoded['startDate']?.toString().trim();
    DateTime? semesterStart;
    if (startDateRaw != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(startDateRaw)) {
      final parsed = DateTime.tryParse(startDateRaw);
      if (parsed != null) {
        semesterStart =
            parsed.subtract(Duration(days: parsed.weekday - 1));
      }
    }

    final sectionTimes = _parseTimeSlots(decoded['timeSlots']);
    final effectiveMaxSections = sectionTimes != null &&
            sectionTimes.length > maxSections
        ? sectionTimes.length
        : maxSections;

    final courses = <Course>[];
    final warnings = <String>[];

    for (var i = 0; i < rawCourses.length; i++) {
      final item = rawCourses[i];
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        warnings.add('第 ${i + 1} 条课程缺少名称，已跳过');
        continue;
      }

      final dayRaw = item['day'];
      final weekday = dayRaw is num
          ? dayRaw.toInt()
          : (EduParsers.parseWeekday(dayRaw?.toString()) ?? 0);
      if (weekday < 1 || weekday > 7) {
        warnings.add('「$name」星期无法识别：$dayRaw');
        continue;
      }

      final startNode = (item['startNode'] as num?)?.toInt() ?? 0;
      var step = (item['step'] as num?)?.toInt() ?? 1;
      if (startNode < 1 || startNode > effectiveMaxSections) {
        warnings.add('「$name」起始节次超出范围：$startNode');
        continue;
      }
      if (step < 1) step = 1;
      if (startNode + step - 1 > effectiveMaxSections) {
        step = effectiveMaxSections - startNode + 1;
      }

      final rawWeeks = item['weeks'];
      List<int> weeks;
      if (rawWeeks is List<dynamic>) {
        weeks = rawWeeks
            .whereType<num>()
            .map((e) => e.toInt())
            .where((w) => w >= 1 && w <= effectiveMaxWeeks)
            .toSet()
            .toList()
          ..sort();
      } else {
        weeks = EduParsers.parseWeeksExpression(
          rawWeeks?.toString() ?? '',
          maxWeeks: effectiveMaxWeeks,
        );
      }

      if (weeks.isEmpty) {
        warnings.add('「$name」未提供有效周次，已默认 1-$effectiveMaxWeeks 周');
        weeks = [for (int w = 1; w <= effectiveMaxWeeks; w++) w];
      }

      courses.add(
        Course(
          id: 'ai_${DateTime.now().microsecondsSinceEpoch}_$i',
          name: name,
          teacher: (item['teacher'] ?? '').toString().trim(),
          location: (item['location'] ?? '').toString().trim(),
          note: (item['note'] ?? '').toString().trim(),
          weekday: weekday,
          startSection: startNode,
          sectionCount: step,
          weeks: weeks,
          colorValue: EduParsers.colorForName(name),
          source: 'import',
        ),
      );
    }

    return ImportPayload(
      courses: courses,
      warnings: warnings,
      sourceLabel: 'AI 一键转换',
      semesterStart: semesterStart,
      totalWeeks:
          totalWeeksRaw != null && totalWeeksRaw >= 1 && totalWeeksRaw <= 40
              ? totalWeeksRaw
              : null,
      sectionTimes: sectionTimes,
    );
  }

  static String _extractJsonString(String raw) {
    var text = raw.trim();
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1)!.trim();
    }
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return text.substring(firstBrace, lastBrace + 1);
    }
    return text;
  }

  static List<SectionTime>? _parseTimeSlots(dynamic raw) {
    if (raw is! List<dynamic> || raw.isEmpty) return null;
    final items = <({int node, SectionTime time})>[];
    final hmRe = RegExp(r'^(\d{1,2}):(\d{2})$');

    for (final entry in raw) {
      if (entry is! Map) return null;
      final node = (entry['node'] as num?)?.toInt() ??
          (entry['index'] as num?)?.toInt() ??
          0;
      final start = (entry['startTime'] ?? '').toString().trim();
      final end = (entry['endTime'] ?? '').toString().trim();
      if (node < 1 || !hmRe.hasMatch(start) || !hmRe.hasMatch(end)) {
        return null;
      }
      items.add((
        node: node,
        time: SectionTime(
          start: _padHm(start),
          end: _padHm(end),
        ),
      ));
    }

    items.sort((a, b) => a.node.compareTo(b.node));
    for (var i = 0; i < items.length; i++) {
      if (items[i].node != i + 1) return null;
    }
    return items.map((e) => e.time).toList();
  }

  static String _padHm(String hm) {
    final parts = hm.split(':');
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }
}
