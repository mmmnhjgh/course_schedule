import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/course_adjustment.dart';
import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import 'ai_import_service.dart';
import 'edu_parsers.dart';
import 'schedule_occurrences.dart';
import 'storage_service.dart';

typedef FileImportResult = ({ImportPayload? payload, ScheduleLibrary? backup});

/// 多格式文件导入与日历分享服务（支持 .xlsx / .csv / .ics / .json）
class FileImportService {
  /// 打开系统文件选择器并解析所选课表文件
  static Future<FileImportResult?> pickAndParseFile({
    required ScheduleConfig currentConfig,
    bool backupOnly = false,
  }) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: backupOnly
          ? ['json', 'txt']
          : ['xlsx', 'csv', 'ics', 'json', 'txt'],
    );
    if (picked.isEmpty) return null;

    final file = picked.first;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('所选文件为空');
    }
    if (backupOnly) {
      final raw = jsonDecode(utf8.decode(bytes).trim());
      return (payload: null, backup: ScheduleLibrary.fromBackup(raw));
    }

    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'xlsx') {
      return (
        payload: parseXlsxBytes(
          bytes,
          maxWeeks: currentConfig.totalWeeks,
          maxSections: currentConfig.maxSections,
        ),
        backup: null,
      );
    }

    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (ext == 'ics' || text.trimLeft().startsWith('BEGIN:VCALENDAR')) {
      return (payload: parseIcs(text, currentConfig), backup: null);
    }
    if (ext == 'json' ||
        text.trimLeft().startsWith('{') ||
        text.trimLeft().startsWith('[')) {
      return parseJsonInput(text, currentConfig);
    }
    return (
      payload: parseCsv(
        text,
        maxWeeks: currentConfig.totalWeeks,
        maxSections: currentConfig.maxSections,
      ),
      backup: null,
    );
  }

  static FileImportResult parseJsonInput(String text, ScheduleConfig config) {
    final trimmed = text.trim();
    ImportPayload parseAi() => AiImportService.parseAiJson(
      trimmed,
      defaultMaxWeeks: config.totalWeeks,
      maxSections: config.maxSections,
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      if (!trimmed.contains('"startNode"')) rethrow;
      return (payload: parseAi(), backup: null);
    }
    if (decoded is Map<String, dynamic> && decoded['courses'] is List) {
      final rawCourses = decoded['courses'] as List<dynamic>;
      final looksLikeAiSchema = rawCourses.isNotEmpty &&
          rawCourses.first is Map &&
          (rawCourses.first as Map).containsKey('startNode');
      if (looksLikeAiSchema) {
        return (payload: parseAi(), backup: null);
      }
    }

    final backup = ScheduleLibrary.fromBackup(decoded);
    if (ScheduleLibrary.isBackup(decoded)) {
      return (payload: null, backup: backup);
    }
    return (
      payload: ImportPayload(
        courses: backup.profiles.single.courses,
        sourceLabel: 'JSON 课表',
      ),
      backup: null,
    );
  }

  /* ---------- CSV 解析（RFC 4180 + 自动识别分隔符与表头列） ---------- */

  static String detectDelimiter(String text) {
    final first = text
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    var best = ',';
    var bestCount = -1;
    for (final d in [',', '\t', ';']) {
      final count = d.allMatches(first).length;
      if (count > bestCount) {
        best = d;
        bestCount = count;
      }
    }
    return best;
  }

  static List<List<String>> parseCsvRows(String text, String delim) {
    final rows = <List<String>>[];
    var cells = <String>[];
    final cell = StringBuffer();
    var quoted = false;

    void endRow() {
      cells.add(cell.toString());
      if (cells.any((c) => c.trim().isNotEmpty)) {
        rows.add(cells.map((c) => c.trim()).toList());
      }
      cells = [];
      cell.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.toString().trim().isEmpty) {
        cell.clear();
        quoted = true;
      } else if (ch == delim) {
        cells.add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        endRow();
      } else {
        cell.write(ch);
      }
    }
    endRow();
    return rows;
  }

  static ImportPayload parseCsv(
    String text, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final cleaned = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    final delim = detectDelimiter(cleaned);
    final rows = parseCsvRows(cleaned, delim);
    return _parseTabularRows(
      rows,
      sourceLabel: 'CSV 表格',
      maxWeeks: maxWeeks,
      maxSections: maxSections,
    );
  }

  /* ---------- Excel (.xlsx) 解析 ---------- */

  static ImportPayload parseXlsxBytes(
    List<int> bytes, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('Excel 文件中没有工作表');
    }
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows
        .map((row) => row.map((cell) => _cellToString(cell?.value)).toList())
        .where((row) => row.any((c) => c.isNotEmpty))
        .toList();

    return _parseTabularRows(
      rows,
      sourceLabel: 'Excel 表格',
      maxWeeks: maxWeeks,
      maxSections: maxSections,
    );
  }

  static String _cellToString(CellValue? value) {
    if (value == null) return '';
    if (value is DoubleCellValue) {
      final d = value.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return value.toString().trim();
  }

  static ImportPayload _parseTabularRows(
    List<List<String>> rows, {
    required String sourceLabel,
    required int maxWeeks,
    required int maxSections,
  }) {
    if (rows.isEmpty) {
      return ImportPayload(
        courses: const [],
        warnings: const ['表格内容为空'],
        sourceLabel: sourceLabel,
      );
    }

    // 尝试从首行自动识别表头列映射
    final header = rows.first.map((e) => e.toLowerCase()).toList();
    int? findCol(List<String> keywords) {
      for (var i = 0; i < header.length; i++) {
        if (keywords.any((k) => header[i].contains(k))) return i;
      }
      return null;
    }

    final nameCol = findCol(['课程', '课名', '科目', 'name', 'course']);
    final weekdayCol = findCol(['星期', '周几', 'day', 'weekday']);
    final periodCol = findCol(['节次', '节数', '时间', 'period', 'section']);
    final weeksCol = findCol(['周次', '周数', 'weeks', 'week']);
    final locationCol = findCol(['地点', '教室', 'location', 'room']);
    final teacherCol = findCol(['教师', '老师', '任课', 'teacher']);

    final hasHeader = nameCol != null && weekdayCol != null;
    final startRow = hasHeader ? 1 : 0;
    final cName = nameCol ?? 0;
    final cWeekday = weekdayCol ?? 1;
    final cPeriod = periodCol ?? 2;
    final cWeeks = weeksCol ?? 3;
    final cLocation = locationCol ?? 4;
    final cTeacher = teacherCol ?? 5;

    final courses = <Course>[];
    final warnings = <String>[];

    for (var r = startRow; r < rows.length; r++) {
      final row = rows[r];
      String cellAt(int col) => col >= 0 && col < row.length ? row[col].trim() : '';

      final name = cellAt(cName);
      if (name.isEmpty) continue;

      final weekday = EduParsers.parseWeekday(cellAt(cWeekday));
      if (weekday == null) {
        warnings.add('第 ${r + 1} 行星期无法识别：${cellAt(cWeekday)}');
        continue;
      }

      final sec = EduParsers.parseSectionRange(cellAt(cPeriod));
      if (sec == null || sec.start > maxSections) {
        warnings.add('第 ${r + 1} 行节次无法识别：${cellAt(cPeriod)}');
        continue;
      }
      final clampedEnd = sec.end.clamp(sec.start, maxSections);

      final rawWeeks = cellAt(cWeeks);
      var weeks = EduParsers.parseWeeksExpression(rawWeeks, maxWeeks: maxWeeks);
      if (weeks.isEmpty) {
        weeks = [for (int w = 1; w <= maxWeeks; w++) w];
      }

      courses.add(
        Course(
          id: 'tab_${DateTime.now().microsecondsSinceEpoch}_$r',
          name: name,
          weekday: weekday,
          startSection: sec.start,
          sectionCount: clampedEnd - sec.start + 1,
          weeks: weeks,
          location: cellAt(cLocation),
          teacher: cellAt(cTeacher),
          colorValue: EduParsers.colorForName(name),
          source: 'import',
        ),
      );
    }

    return ImportPayload(
      courses: courses,
      warnings: warnings,
      sourceLabel: sourceLabel,
    );
  }

  /* ---------- ICS 日历导入与导出（兼容 X-TT-SEMESTER 与 X-TT-COLOR） ---------- */

  static ImportPayload parseIcs(String text, ScheduleConfig currentConfig) {
    final unfolded =
        text.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'));
    ScheduleConfig? embeddedConfig;
    final events = <_IcsEvent>[];
    _IcsEvent? cur;

    for (final line in unfolded) {
      if (line.toUpperCase().startsWith('BEGIN:VEVENT')) {
        cur = _IcsEvent();
      } else if (line.toUpperCase().startsWith('END:VEVENT')) {
        if (cur != null) events.add(cur);
        cur = null;
      } else {
        final idx = line.indexOf(':');
        if (idx < 0) continue;
        final rawKey = line.substring(0, idx).split(';').first.toUpperCase();
        final val = _unescapeIcs(line.substring(idx + 1).trim());
        if (cur == null) {
          if (rawKey == 'X-TT-SEMESTER') {
            embeddedConfig = _tryParseEmbeddedSemester(val, currentConfig);
          }
          continue;
        }
        switch (rawKey) {
          case 'SUMMARY':
            cur.summary = val;
          case 'LOCATION':
            cur.location = val;
          case 'DESCRIPTION':
            cur.description = val;
          case 'DTSTART':
            cur.dtStart = val;
          case 'DTEND':
            cur.dtEnd = val;
          case 'RRULE':
            cur.rrule = val;
          case 'EXDATE':
            cur.exdates.addAll(val.split(',').map((e) => e.trim()));
          case 'STATUS':
            cur.status = val.toUpperCase();
          case 'X-TT-COLOR':
            cur.colorHex = val;
        }
      }
    }

    final cfg = embeddedConfig ?? currentConfig;
    final courses = <Course>[];
    final warnings = <String>[];
    final bySlot =
        <
          (String, int, int, int, String, String, int),
          ({Course base, Set<int> weekSet})
        >{};

    for (final ev in events) {
      if (ev.summary.isEmpty ||
          ev.dtStart.isEmpty ||
          !ev.dtStart.contains('T') ||
          ev.status == 'CANCELLED') {
        continue;
      }
      final startDt = _parseIcsDateTime(ev.dtStart);
      if (startDt == null) continue;
      final endDt = _parseIcsDateTime(ev.dtEnd) ??
          startDt.add(const Duration(minutes: 90));

      final startMin = startDt.hour * 60 + startDt.minute;
      final endMin = endDt.hour * 60 + endDt.minute;
      final sec = _matchSectionsFromMinutes(cfg, startMin, endMin);
      if (sec == null) {
        warnings.add('「${ev.summary}」时间不在作息表内，已跳过');
        continue;
      }

      final weeks = _expandIcsWeeks(cfg, startDt, ev.rrule, ev.exdates);
      if (weeks.isEmpty) continue;

      final weekday = startDt.weekday;
      final colorVal = _parseHexColor(ev.colorHex) ??
          EduParsers.colorForName(ev.summary);
      final teacher = _extractTeacherFromDesc(ev.description, ev.location);
      final key = (
        ev.summary,
        weekday,
        sec.start,
        sec.end,
        teacher,
        ev.location,
        colorVal,
      );

      if (bySlot.containsKey(key)) {
        bySlot[key]!.weekSet.addAll(weeks);
      } else {
        bySlot[key] = (
          base: Course(
            id: 'ics_${DateTime.now().microsecondsSinceEpoch}_${bySlot.length}',
            name: ev.summary,
            teacher: teacher,
            location: ev.location,
            weekday: weekday,
            startSection: sec.start,
            sectionCount: sec.end - sec.start + 1,
            weeks: weeks,
            colorValue: colorVal,
            source: 'import',
          ),
          weekSet: weeks.toSet(),
        );
      }
    }

    for (final entry in bySlot.values) {
      final sorted = entry.weekSet.toList()..sort();
      courses.add(entry.base.copyWith(weeks: sorted));
    }

    return ImportPayload(
      courses: courses,
      warnings: warnings,
      sourceLabel: 'ICS 日历文件',
      semesterStart: embeddedConfig?.semesterStart,
      totalWeeks: embeddedConfig?.totalWeeks,
      sectionTimes: embeddedConfig?.sectionTimes,
    );
  }

  /// 生成标准 RFC 5545 `.ics` 日历文本（附带 X-TT-SEMESTER 以便同学间原样导入）
  static String exportIcs({
    required List<Course> courses,
    required ScheduleConfig config,
    String scheduleName = '轻课表',
    List<CourseAdjustment> adjustments = const [],
  }) {
    final buf = StringBuffer();
    buf.writeln('BEGIN:VCALENDAR');
    buf.writeln('VERSION:2.0');
    buf.writeln('PRODID:-//QingKebiao//Flutter Timetable//CN');
    buf.writeln('CALSCALE:GREGORIAN');
    buf.writeln('X-WR-CALNAME:${_escapeIcs(scheduleName)}');

    final semesterMeta = jsonEncode({
      'name': scheduleName,
      'startDate': _fmtYmd(config.firstMonday),
      'totalWeeks': config.totalWeeks,
      'timeGrid': List.generate(
        config.maxSections.clamp(0, config.sectionTimes.length),
        (i) => {
          'index': i + 1,
          'start': _hhmmToMinutes(config.sectionTimes[i].start),
          'end': _hhmmToMinutes(config.sectionTimes[i].end),
        },
      ),
    });
    buf.writeln('X-TT-SEMESTER:${_escapeIcs(semesterMeta)}');

    final timetable = ScheduleOccurrences(
      ScheduleProfile(
        id: 'export',
        name: scheduleName,
        courses: courses,
        config: config,
        adjustments: adjustments,
      ),
    );
    for (final occurrence in timetable.all) {
      final course = occurrence.course;
      final range = config.sectionMinutes(
        course.startSection,
        course.endSection,
      );
      if (range == null) continue;

      final startHm = _formatIcsClock(range.start);
      final endHm = _formatIcsClock(range.end);
      final colorHex =
          '#${(course.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      final ymd = ScheduleConfig.dateKey(occurrence.date).replaceAll('-', '');
      final adjustment = occurrence.adjustment;
      final source = adjustment != null && timetable.hasOriginal(adjustment)
          ? adjustment
          : null;
      final week = config.teachingWeek(source?.originalDate ?? occurrence.date);
      final identity = source?.originalCourseId ?? course.id;
      buf.writeln('BEGIN:VEVENT');
      buf.writeln('UID:$identity-w$week@qingkebiao');
      buf.writeln('SUMMARY:${_escapeIcs(course.name)}');
      buf.writeln('DTSTART:${ymd}T${startHm}00');
      buf.writeln('DTEND:${ymd}T${endHm}00');
      if (course.location.isNotEmpty) {
        buf.writeln('LOCATION:${_escapeIcs(course.location)}');
      }
      final description = [
        if (course.teacher.isNotEmpty) course.teacher,
        if (course.note.isNotEmpty) course.note,
      ];
      if (description.isNotEmpty) {
        buf.writeln('DESCRIPTION:${_escapeIcs(description.join('\n'))}');
      }
      buf.writeln('X-TT-COLOR:$colorHex');
      buf.writeln('END:VEVENT');
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  /// 将文本写为临时文件并调起系统原生分享面板
  static Future<void> shareTextAsFile({
    required String filename,
    required String content,
    required String shareSubject,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsString(content, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: shareSubject,
      ),
    );
  }

  /* ---------- ICS 私有辅助方法 ---------- */

  static ScheduleConfig? _tryParseEmbeddedSemester(
    String rawJson,
    ScheduleConfig fallback,
  ) {
    try {
      final map = jsonDecode(rawJson);
      if (map is! Map<String, dynamic>) return null;
      final startDateStr = map['startDate']?.toString();
      final totalWeeks = (map['totalWeeks'] as num?)?.toInt();
      if (startDateStr == null || totalWeeks == null) return null;
      final parsedStart = DateTime.tryParse(startDateStr);
      if (parsedStart == null) return null;

      final rawGrid = map['timeGrid'] as List<dynamic>?;
      List<SectionTime>? times;
      if (rawGrid != null && rawGrid.isNotEmpty) {
        times = rawGrid.whereType<Map>().map((t) {
          final sMin = (t['start'] as num?)?.toInt() ?? 480;
          final eMin = (t['end'] as num?)?.toInt() ?? 525;
          return SectionTime(
            start: _minutesToHhmm(sMin),
            end: _minutesToHhmm(eMin),
          );
        }).toList();
      }
      return fallback.copyWith(
        semesterStart: parsedStart,
        totalWeeks: totalWeeks.clamp(1, 40),
        maxSections: times != null ? times.length : fallback.maxSections,
        sectionTimes: times ?? fallback.sectionTimes,
      );
    } catch (_) {
      return null;
    }
  }

  static ({int start, int end})? _matchSectionsFromMinutes(
    ScheduleConfig cfg,
    int startMin,
    int endMin,
  ) {
    final times = cfg.sectionTimes;
    final limit = cfg.maxSections.clamp(0, times.length);
    int? startSec;
    int? endSec;

    for (var i = 0; i < limit; i++) {
      final s = _hhmmToMinutes(times[i].start);
      final e = _hhmmToMinutes(times[i].end);
      if (startSec == null && (startMin <= s || (startMin >= s && startMin < e))) {
        startSec = i + 1;
      }
      if (endMin >= e || (endMin > s && endMin <= e)) {
        endSec = i + 1;
      }
    }
    if (startSec == null || endSec == null || endSec < startSec) return null;
    return (start: startSec, end: endSec);
  }

  static List<int> _expandIcsWeeks(
    ScheduleConfig cfg,
    DateTime startDt,
    String rrule,
    List<String> exdates,
  ) {
    int signedWeek(DateTime date) {
      final days = cfg.daysFromFirstMonday(date);
      return (days < 0 ? days - 6 : days) ~/ 7 + 1;
    }

    final w0 = signedWeek(startDt);

    if (rrule.isEmpty) {
      return (w0 >= 1 && w0 <= cfg.totalWeeks) ? [w0] : [];
    }

    final skipWeeks = <int>{};
    for (final ex in exdates) {
      final dt = _parseIcsDateTime(ex);
      if (dt != null) {
        skipWeeks.add(signedWeek(dt));
      }
    }

    final parts = <String, String>{};
    for (final seg in rrule.split(';')) {
      final eq = seg.indexOf('=');
      if (eq > 0) {
        parts[seg.substring(0, eq).toUpperCase()] = seg.substring(eq + 1);
      }
    }
    if (parts['FREQ']?.toUpperCase() != 'WEEKLY') {
      return (w0 >= 1 && w0 <= cfg.totalWeeks) ? [w0] : [];
    }

    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    if (interval < 1) return [];
    var count = parts['COUNT'] != null ? int.tryParse(parts['COUNT']!) : null;
    var untilWeek = cfg.totalWeeks;
    if (parts['UNTIL'] != null) {
      final u = _parseIcsDateTime(parts['UNTIL']!);
      if (u != null) {
        untilWeek = signedWeek(u).clamp(0, cfg.totalWeeks);
        if (cfg.dateOf(untilWeek, startDt.weekday).isAfter(u)) untilWeek--;
      }
    }

    final weeks = <int>[];
    final skipped = w0 < 1 ? (1 - w0 + interval - 1) ~/ interval : 0;
    if (count != null) count -= skipped;
    for (
      var w = w0 + skipped * interval;
      w <= untilWeek && (count == null || count > 0);
      w += interval
    ) {
      if (w >= 1 && w <= cfg.totalWeeks && !skipWeeks.contains(w)) {
        weeks.add(w);
      }
      if (count != null) count--;
    }
    return weeks;
  }

  static DateTime? _parseIcsDateTime(String v) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$')
        .firstMatch(v.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = m.group(4) != null ? int.parse(m.group(4)!) : 0;
    final mi = m.group(5) != null ? int.parse(m.group(5)!) : 0;
    final s = m.group(6) != null ? int.parse(m.group(6)!) : 0;
    if (m.group(7) == 'Z') {
      return DateTime.utc(y, mo, d, h, mi, s).toLocal();
    }
    return DateTime(y, mo, d, h, mi, s);
  }

  static int? _parseHexColor(String? hex) {
    if (hex == null) return null;
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
    if (m == null) return null;
    return int.parse('FF${m.group(1)!}', radix: 16);
  }

  static String _extractTeacherFromDesc(String desc, String location) {
    if (desc.isEmpty) return '';
    for (final line in desc.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty && t != location) return t;
    }
    return '';
  }

  static String _formatIcsClock(int minutes) {
    final hours = (minutes ~/ 60).toString().padLeft(2, '0');
    final remainder = (minutes % 60).toString().padLeft(2, '0');
    return '$hours$remainder';
  }

  static int _hhmmToMinutes(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return 480;
    return (int.tryParse(p[0]) ?? 8) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  static String _minutesToHhmm(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final min = (m % 60).toString().padLeft(2, '0');
    return '$h:$min';
  }

  static String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _escapeIcs(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  static String _unescapeIcs(String s) => s
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');
}

class _IcsEvent {
  String summary = '';
  String location = '';
  String description = '';
  String dtStart = '';
  String dtEnd = '';
  String rrule = '';
  List<String> exdates = [];
  String status = '';
  String? colorHex;
}
