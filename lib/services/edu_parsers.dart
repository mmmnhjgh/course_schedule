import '../models/course.dart';
import '../widgets/course_edit_sheet.dart';

/// 教务系统类型
enum WebAcademicType {
  auto('自动识别（推荐）'),
  zhengfangNew('新版正方教务'),
  qiangzhi('强智教务'),
  genericTable('通用课表表格');

  final String label;
  const WebAcademicType(this.label);
}

/// 统一课表导入结果
class EduParseResult {
  final List<Course> courses;
  final List<String> warnings;
  final String sourceTag;

  const EduParseResult({
    required this.courses,
    this.warnings = const [],
    this.sourceTag = '',
  });
}

/// 纯 Dart 教务与通用课表解析器（支持正方接口 JSON、强智 HTML、通用 HTML 表格）
class EduParsers {
  static int colorForName(String name) {
    final idx = name.hashCode.abs() % kCourseColorPresets.length;
    return kCourseColorPresets[idx];
  }

  /// 根据 URL 指纹识别教务系统类型
  static WebAcademicType? detectSystem(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/jwglxt/')) return WebAcademicType.zhengfangNew;
    if (lower.contains('/jsxsd/')) return WebAcademicType.qiangzhi;
    return null;
  }

  /// 根据 URL 和页面标题判断是否已进入课表页
  static bool isLikelyTimetablePage(
    WebAcademicType? system,
    String url,
    String title,
  ) {
    if (system == WebAcademicType.zhengfangNew) {
      return RegExp(r'kbcx|xskbcx', caseSensitive: false).hasMatch(url);
    }
    if (RegExp(r'课表|课程表|上课安排').hasMatch(title)) return true;
    return RegExp(
      r'\b(kb|kcb|kebiao|timetable|schedule|xskb|curriculum)\b|kbcx|kcbcx|xskb',
      caseSensitive: false,
    ).hasMatch(url);
  }

  /// 解析星期（支持 "1"~"7"、"周一"、"星期三"、"Wednesday" 等）
  static int? parseWeekday(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final numOnly = int.tryParse(s);
    if (numOnly != null && numOnly >= 1 && numOnly <= 7) return numOnly;

    const cnMap = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    for (final entry in cnMap.entries) {
      if (s.contains(entry.key)) return entry.value;
    }

    final lower = s.toLowerCase();
    if (lower.contains('mon')) return 1;
    if (lower.contains('tue')) return 2;
    if (lower.contains('wed')) return 3;
    if (lower.contains('thu')) return 4;
    if (lower.contains('fri')) return 5;
    if (lower.contains('sat')) return 6;
    if (lower.contains('sun')) return 7;
    return null;
  }

  /// 解析节次范围：支持 "3-4"、"0304"、"第1-2节"、"5"
  static ({int start, int end})? parseSectionRange(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final rangeMatch = RegExp(r'(\d{1,2})\s*[-–—~至到]\s*(\d{1,2})').firstMatch(s);
    if (rangeMatch != null) {
      final a = int.parse(rangeMatch.group(1)!);
      final b = int.parse(rangeMatch.group(2)!);
      if (a >= 1 && b >= a) return (start: a, end: b);
    }

    // 兼容 "3,4" / "3、4" 逗号分隔节次
    if (RegExp(r'^\d{1,2}(?:\s*[,，、]\s*\d{1,2})+$').hasMatch(s)) {
      final nums = RegExp(r'\d{1,2}')
          .allMatches(s)
          .map((m) => int.parse(m.group(0)!))
          .where((n) => n >= 1)
          .toList()
        ..sort();
      if (nums.isNotEmpty) {
        return (start: nums.first, end: nums.last);
      }
    }

    // 兼容正方常见 "0304"、"010203" 两位数字拼接节次
    if (RegExp(r'^\d{4,}$').hasMatch(s) && s.length.isEven) {
      final nums = <int>[];
      for (var i = 0; i < s.length; i += 2) {
        nums.add(int.parse(s.substring(i, i + 2)));
      }
      nums.sort();
      if (nums.isNotEmpty && nums.first >= 1) {
        return (start: nums.first, end: nums.last);
      }
    }

    final single = RegExp(r'(\d{1,2})').firstMatch(s);
    if (single != null) {
      final n = int.parse(single.group(1)!);
      if (n >= 1) return (start: n, end: n);
    }
    return null;
  }

  /// 解析周次表达式（每段的单双周仅作用于本段）："1-8周(单), 10-16周"
  static List<int> parseWeeksExpression(String expr, {int maxWeeks = 25}) {
    if (expr.trim().isEmpty) return [];
    final normalized = expr
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('，', ',')
        .replaceAll('、', ',')
        .replaceAll(';', ',')
        .replaceAll('；', ',')
        .replaceAll('~', '-')
        .replaceAll('至', '-')
        .replaceAll('到', '-');

    final result = <int>{};
    for (final rawPart in normalized.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;

      final isOddOnly = part.contains('单');
      final isEvenOnly = part.contains('双');

      final rangeMatch = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(part);
      if (rangeMatch != null) {
        var start = int.tryParse(rangeMatch.group(1)!) ?? 1;
        var end = int.tryParse(rangeMatch.group(2)!) ?? start;
        if (start > end) {
          final tmp = start;
          start = end;
          end = tmp;
        }
        for (var w = start; w <= end; w++) {
          if (w < 1 || w > maxWeeks) continue;
          if (isOddOnly && w.isEven) continue;
          if (isEvenOnly && w.isOdd) continue;
          result.add(w);
        }
        continue;
      }

      for (final numMatch in RegExp(r'\d+').allMatches(part)) {
        final w = int.tryParse(numMatch.group(0)!);
        if (w != null && w >= 1 && w <= maxWeeks) {
          if (isOddOnly && w.isEven) continue;
          if (isEvenOnly && w.isOdd) continue;
          result.add(w);
        }
      }
    }

    final sorted = result.toList()..sort();
    return sorted;
  }

  /// 解析新版正方个人课表接口 `xskbcx_cxXsgrkb.html` 返回的 kbList
  static EduParseResult parseZhengfangKbList(
    dynamic input, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final List<dynamic> list;
    if (input is List<dynamic>) {
      list = input;
    } else if (input is Map<String, dynamic> &&
        input['kbList'] is List<dynamic>) {
      list = input['kbList'] as List<dynamic>;
    } else {
      return const EduParseResult(
        courses: [],
        warnings: ['正方接口未返回有效课程列表'],
        sourceTag: 'zhengfangApi',
      );
    }

    final courses = <Course>[];
    final warnings = <String>[];
    final dedup = <String>{};

    for (var i = 0; i < list.length; i++) {
      final raw = list[i];
      if (raw is! Map) continue;
      final name = _cleanStr(raw['kcmc']);
      if (name.isEmpty) continue;

      final weekday = int.tryParse(_cleanStr(raw['xqj'])) ?? 0;
      if (weekday < 1 || weekday > 7) {
        warnings.add('「$name」星期无法识别：${raw['xqj']}');
        continue;
      }

      final sec = parseSectionRange(_cleanStr(raw['jcs']));
      if (sec == null || sec.start > maxSections) {
        warnings.add('「$name」节次超出范围或无法识别：${raw['jcs']}');
        continue;
      }
      final clampedEnd = sec.end.clamp(sec.start, maxSections);

      final zcd = _cleanStr(raw['zcd']);
      var weeks = parseWeeksExpression(zcd, maxWeeks: maxWeeks);
      if (weeks.isEmpty) {
        weeks = [for (int w = 1; w <= maxWeeks; w++) w];
        warnings.add('「$name」周次无法识别（$zcd），已默认 1-$maxWeeks 周');
      }

      final dedupKey = '$name|$weekday|${sec.start}|${weeks.join(",")}';
      if (!dedup.add(dedupKey)) continue;

      courses.add(
        Course(
          id: 'zf_${DateTime.now().microsecondsSinceEpoch}_$i',
          name: name,
          teacher: _cleanStr(raw['xm']),
          location: _cleanStr(raw['cdmc']),
          weekday: weekday,
          startSection: sec.start,
          sectionCount: clampedEnd - sec.start + 1,
          weeks: weeks,
          colorValue: colorForName(name),
          source: 'import',
        ),
      );
    }

    return EduParseResult(
      courses: courses,
      warnings: warnings,
      sourceTag: 'zhengfangApi',
    );
  }

  /// 解析强智教务 `table#kbtable` HTML
  static EduParseResult parseQiangzhiTableHtml(
    String html, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final table = _findQzTable(html);
    if (table == null) {
      return const EduParseResult(
        courses: [],
        warnings: ['未找到强智课表表格'],
        sourceTag: 'qiangzhiHtml',
      );
    }

    final rows = RegExp(r'<tr\b[^>]*>[\s\S]*?<\/tr>', caseSensitive: false)
        .allMatches(table)
        .map((m) => m.group(0)!)
        .toList();
    if (rows.length < 2) {
      return const EduParseResult(
        courses: [],
        warnings: ['强智课表表格为空'],
        sourceTag: 'qiangzhiHtml',
      );
    }

    // 查找表头行（含至少 5 个星期列）
    var headerIdx = -1;
    var colWeekdays = <int>[];
    for (var i = 0; i < rows.length && i < 3; i++) {
      final cells = _cellsOfRow(rows[i])
          .map((c) => _linesOfCell(c).join(' '))
          .toList();
      final wds = cells.map((h) => _headerWeekday(h) ?? 0).toList();
      if (wds.where((w) => w > 0).length >= 5) {
        headerIdx = i;
        colWeekdays = wds;
        break;
      }
    }
    if (headerIdx < 0) {
      return const EduParseResult(
        courses: [],
        warnings: ['强智课表表头无法识别'],
        sourceTag: 'qiangzhiHtml',
      );
    }

    var maxCol = 0;
    for (var i = 0; i < colWeekdays.length; i++) {
      if (colWeekdays[i] > 0) maxCol = i;
    }

    final courses = <Course>[];
    final warnings = <String>[];
    final dedup = <String>{};
    final weeksLineRe = RegExp(r'[(（]周[)）]|^\d[\d,.\-]*\s*周');

    for (var r = headerIdx + 1; r < rows.length; r++) {
      final cells = _cellsOfRow(rows[r]);
      if (cells.isEmpty) continue;
      final firstText = _linesOfCell(cells.first).join(' ');
      if (firstText.contains('备注') || cells.length <= maxCol) continue;

      final fallbackSec = _headerPeriods(cells.first);

      for (var c = 0; c < colWeekdays.length && c < cells.length; c++) {
        final weekday = colWeekdays[c];
        if (weekday <= 0) continue;

        final blocks = _extractQzCourseBlocks(cells[c]);
        for (var b = 0; b < blocks.length; b++) {
          final block = blocks[b];
          if (block.isEmpty) continue;

          // 去掉强智课名尾部调课红字标记 O / P
          final name = block.first.replaceFirst(RegExp(r'\s+[OP]$'), '').trim();
          if (name.isEmpty) continue;

          var weekLineIdx = -1;
          for (var k = 1; k < block.length; k++) {
            if (weeksLineRe.hasMatch(block[k])) {
              weekLineIdx = k;
              break;
            }
          }
          if (weekLineIdx < 0) {
            warnings.add('「$name」未识别出周次行，已跳过');
            continue;
          }

          final weeksLine = block[weekLineIdx];
          final bracketMatch = RegExp(r'\[([^\]]*)\]').firstMatch(weeksLine);
          final sec = (bracketMatch != null
                  ? _periodsFromBracket(bracketMatch.group(1)!)
                  : null) ??
              fallbackSec;
          if (sec == null || sec.start > maxSections) {
            warnings.add('「$name」节次无法识别：$weeksLine');
            continue;
          }
          final clampedEnd = sec.end.clamp(sec.start, maxSections);

          final weeksExpr = weeksLine.split('[').first.replaceAllMapped(
                RegExp(r'[（(][^)）]*[)）]'),
                (m) => RegExp(r'[单双]').hasMatch(m.group(0)!) ? m.group(0)! : '',
              );
          final weeks = parseWeeksExpression(weeksExpr, maxWeeks: maxWeeks);
          if (weeks.isEmpty) {
            warnings.add('「$name」周次无法识别：$weeksLine');
            continue;
          }

          final teacher = block.sublist(1, weekLineIdx).join(' ').trim();
          final location = block.sublist(weekLineIdx + 1).join(' ').trim();
          final dedupKey = '$name|$weekday|${sec.start}|${weeks.join(",")}';
          if (!dedup.add(dedupKey)) continue;

          courses.add(
            Course(
              id: 'qz_${DateTime.now().microsecondsSinceEpoch}_${r}_${c}_$b',
              name: name,
              teacher: teacher,
              location: location,
              weekday: weekday,
              startSection: sec.start,
              sectionCount: clampedEnd - sec.start + 1,
              weeks: weeks,
              colorValue: colorForName(name),
              source: 'import',
            ),
          );
        }
      }
    }

    return EduParseResult(
      courses: courses,
      warnings: warnings,
      sourceTag: 'qiangzhiHtml',
    );
  }

  /// 通用 HTML 表格解析（展开 rowspan / colspan 矩阵）
  static EduParseResult parseGenericHtmlTable(
    String html, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final tables = _extractHtmlTables(html);
    EduParseResult? bestResult;

    for (final table in tables) {
      final matrix = _expandTableMatrix(table);
      if (matrix.length < 2) continue;

      var headerIdx = -1;
      var colWeekdays = <int>[];
      for (var i = 0; i < matrix.length && i < 3; i++) {
        final wds = matrix[i].map((h) => _headerWeekday(h.text) ?? 0).toList();
        if (wds.where((w) => w > 0).length >= 5) {
          headerIdx = i;
          colWeekdays = wds;
          break;
        }
      }
      if (headerIdx < 0) continue;

      final courses = <Course>[];
      final warnings = <String>[];
      final dedup = <String>{};

      for (var r = headerIdx + 1; r < matrix.length; r++) {
        final row = matrix[r];
        if (row.isEmpty) continue;
        final rowStartSec =
            parseSectionRange(row.first.text) ??
            (start: r - headerIdx, end: r - headerIdx);

        for (var c = 0; c < colWeekdays.length && c < row.length; c++) {
          final weekday = colWeekdays[c];
          if (weekday <= 0) continue;
          final cell = row[c];
          if (cell.isContinuation) continue;
          final rawCell = cell.text.trim();
          if (rawCell.length < 2) continue;

          final lines = rawCell
              .split('\n')
              .expand((l) => _splitInlineLabels(l))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (lines.isEmpty) continue;

          final name = lines.first
              .replaceFirst(RegExp(r'^(课程名称?|科目)[:：]\s*'), '')
              .trim();
          var weeksText = '';
          var location = '';
          var teacher = '';

          // 合并跨行 rowspan 覆盖的末尾行节次
          final endRowIdx =
              (r + cell.rowspan - 1).clamp(r, matrix.length - 1);
          final rowEndSec = endRowIdx > r && matrix[endRowIdx].isNotEmpty
              ? (parseSectionRange(matrix[endRowIdx].first.text)?.end ??
                  (rowStartSec.end + cell.rowspan - 1))
              : rowStartSec.end;
          final fallbackSec = (start: rowStartSec.start, end: rowEndSec);

          final sec = _parseExplicitSectionInText(rawCell) ?? fallbackSec;
          if (sec.start > maxSections) continue;

          for (var k = 1; k < lines.length; k++) {
            final line = lines[k];
            if (RegExp(r'^(教师|老师|任课教师)[:：]').hasMatch(line)) {
              teacher = line
                  .replaceFirst(RegExp(r'^(教师|老师|任课教师)[:：]\s*'), '')
                  .trim();
            } else if (RegExp(r'^(地点|教室|上课地点)[:：]').hasMatch(line)) {
              location = line
                  .replaceFirst(RegExp(r'^(地点|教室|上课地点)[:：]\s*'), '')
                  .trim();
            } else if (RegExp(r'^(周次|周数)[:：]').hasMatch(line)) {
              weeksText = line
                  .replaceFirst(RegExp(r'^(周次|周数)[:：]\s*'), '')
                  .trim();
            } else if (weeksText.isEmpty &&
                line.contains('周') &&
                RegExp(r'\d').hasMatch(line)) {
              weeksText = line;
            } else if (location.isEmpty &&
                RegExp(r'楼|室|馆|场|区|房|实验室|\d{3}').hasMatch(line)) {
              location = line;
            } else if (teacher.isEmpty && !line.contains('节')) {
              teacher = line;
            }
          }

          var weeks = parseWeeksExpression(weeksText, maxWeeks: maxWeeks);
          if (weeks.isEmpty) {
            weeks = [for (int w = 1; w <= maxWeeks; w++) w];
          }
          final clampedEnd = sec.end.clamp(sec.start, maxSections);
          final dedupKey = '$name|$weekday|${sec.start}|${weeks.join(",")}';
          if (!dedup.add(dedupKey)) continue;

          courses.add(
            Course(
              id: 'html_${DateTime.now().microsecondsSinceEpoch}_${r}_$c',
              name: name,
              teacher: teacher,
              location: location,
              weekday: weekday,
              startSection: sec.start,
              sectionCount: clampedEnd - sec.start + 1,
              weeks: weeks,
              colorValue: colorForName(name),
              source: 'import',
            ),
          );
        }
      }

      if (courses.isNotEmpty &&
          (bestResult == null || courses.length > bestResult.courses.length)) {
        bestResult = EduParseResult(
          courses: courses,
          warnings: warnings,
          sourceTag: 'genericHtml',
        );
      }
    }

    if (bestResult != null) return bestResult;

    return const EduParseResult(
      courses: [],
      warnings: ['页面中未匹配到包含星期表头的课表表格'],
      sourceTag: 'genericHtml',
    );
  }

  /// 按标签深度提取完整的 <table>...</table>，避免嵌套表格导致外层课表被提前截断
  static List<String> _extractHtmlTables(String html) {
    final tokenRe = RegExp(r'<(\/?)table\b[^>]*>', caseSensitive: false);
    final starts = <int>[];
    final tables = <String>[];
    for (final m in tokenRe.allMatches(html)) {
      final isClosing = m.group(1) == '/';
      if (!isClosing) {
        starts.add(m.start);
      } else if (starts.isNotEmpty) {
        final start = starts.removeLast();
        tables.add(html.substring(start, m.end));
      }
    }
    return tables;
  }

  /* ---------- 私有 HTML / 中文数字解析辅助 ---------- */

  static String _cleanStr(dynamic v) =>
      (v == null ? '' : v.toString()).replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _findQzTable(String html) {
    final tables = RegExp(r'<table\b[^>]*>[\s\S]*?<\/table>', caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toList();
    for (final t in tables) {
      final head = t.length > 300 ? t.substring(0, 300) : t;
      if (RegExp(r'''\bid\s*=\s*["']?kbtable["'\s>]''', caseSensitive: false)
          .hasMatch(head)) {
        return t;
      }
    }
    for (final t in tables) {
      if (RegExp(r'''<div\b[^>]*class\s*=\s*["'][^"']*\bkbcontent1?\b''',
              caseSensitive: false)
          .hasMatch(t)) {
        return t;
      }
    }
    return null;
  }

  static List<String> _cellsOfRow(String rowHtml) {
    return RegExp(r'<t[hd]\b[^>]*>([\s\S]*?)<\/t[hd]>', caseSensitive: false)
        .allMatches(rowHtml)
        .map((m) => m.group(1)!)
        .toList();
  }

  static List<String> _splitInlineLabels(String line) {
    final separated = line.replaceAllMapped(
      RegExp(r'(?<!^)\s*(?=(?:教师|老师|任课教师|地点|教室|上课地点|周次|周数)[:：])'),
      (_) => '\n',
    );
    return separated.split('\n');
  }

  static List<String> _linesOfCell(String inner) {
    final text = inner
        .replaceAll(
          RegExp(
            r'<br\s*\/?\s*>|<\/?(?:p|div|li|tr|h[1-6])\b[^>]*>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return text
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static int? _headerWeekday(String h) {
    if (!RegExp(r'(星期|周)\s*[一二三四五六日天1-7]|Mon|Tue|Wed|Thu|Fri|Sat|Sun',
            caseSensitive: false)
        .hasMatch(h)) {
      return null;
    }
    return parseWeekday(h);
  }

  static List<List<String>> _extractQzCourseBlocks(String cellInner) {
    final divs = <({bool expanded, String inner})>[];
    final openRe = RegExp(r'<div\b[^>]*>', caseSensitive: false);
    for (final m in openRe.allMatches(cellInner)) {
      final tag = m.group(0)!;
      final clsMatch =
          RegExp(r'''class\s*=\s*["']([^"']*)["']''', caseSensitive: false)
              .firstMatch(tag);
      if (clsMatch == null) continue;
      final tokens = clsMatch.group(1)!.split(RegExp(r'\s+'));
      final isExpanded = tokens.contains('kbcontent');
      final isCompact = tokens.contains('kbcontent1');
      if (!isExpanded && !isCompact) continue;

      final start = m.end;
      final close = cellInner.indexOf('</div>', start);
      final inner = close < 0 ? '' : cellInner.substring(start, close);
      divs.add((expanded: isExpanded, inner: inner));
    }

    final expandedHasText =
        divs.any((d) => d.expanded && _linesOfCell(d.inner).isNotEmpty);
    final chosen = expandedHasText
        ? divs.where((d) => d.expanded)
        : divs.where((d) => !d.expanded);

    final sepRe = RegExp(r'^[-—–]{3,}$');
    final blocks = <List<String>>[];
    for (final d in chosen) {
      var cur = <String>[];
      for (final line in _linesOfCell(d.inner)) {
        if (sepRe.hasMatch(line)) {
          if (cur.isNotEmpty) blocks.add(cur);
          cur = [];
        } else {
          cur.add(line);
        }
      }
      if (cur.isNotEmpty) blocks.add(cur);
    }
    return blocks;
  }

  static ({int start, int end})? _periodsFromBracket(String inner) {
    final nums = RegExp(r'\d+')
        .allMatches(inner)
        .map((m) => int.parse(m.group(0)!))
        .where((n) => n >= 1)
        .toList();
    if (nums.isEmpty) return null;
    nums.sort();
    return (start: nums.first, end: nums.last);
  }

  static ({int start, int end})? _headerPeriods(String cellInner) {
    final lines = _linesOfCell(cellInner);
    if (lines.isEmpty) return null;
    final core = lines.first.replaceAll(RegExp(r'[第节\s]'), '');
    final direct = parseSectionRange(core);
    if (direct != null) return direct;

    final cnMatch = RegExp(r'[一二三四五六七八九十]+').firstMatch(core);
    if (cnMatch == null) return null;
    final nums = _cnSections(cnMatch.group(0)!);
    if (nums == null || nums.isEmpty) return null;
    nums.sort();
    return (start: nums.first, end: nums.last);
  }

  static int? _cnNumber(String s) {
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (s.isEmpty) return null;
    if (s.length == 1 && digits.containsKey(s)) return digits[s];
    final m = RegExp(r'^([二三四五六七八九])?十([一二三四五六七八九])?$').firstMatch(s);
    if (m == null) return null;
    final tens = m.group(1) != null ? digits[m.group(1)!]! : 1;
    final ones = m.group(2) != null ? digits[m.group(2)!]! : 0;
    return tens * 10 + ones;
  }

  static List<int>? _cnSections(String s) {
    final whole = _cnNumber(s);
    if (whole != null && whole >= 1 && whole <= 30) return [whole];
    final out = <int>[];
    var i = 0;
    while (i < s.length) {
      var adv = 0;
      var val = 0;
      for (final len in [3, 2, 1]) {
        if (i + len > s.length) continue;
        final v = _cnNumber(s.substring(i, i + len));
        if (v != null && v >= 1 && v <= 30) {
          adv = len;
          val = v;
          break;
        }
      }
      if (adv == 0) return null;
      if (out.isNotEmpty &&
          out.last >= 10 &&
          out.last <= 19 &&
          val >= 1 &&
          val <= 9) {
        val += 10;
      }
      out.add(val);
      i += adv;
    }
    return out.isEmpty ? null : out;
  }

  /// 从多行课程文本中仅匹配明确带「节」字的节次范围，避免误把「1-16周」当节次
  static ({int start, int end})? _parseExplicitSectionInText(String raw) {
    final range = RegExp(r'(\d{1,2})\s*[-–—~至到]\s*(\d{1,2})\s*节').firstMatch(raw);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      if (a >= 1 && b >= a) return (start: a, end: b);
    }
    final single = RegExp(r'第\s*(\d{1,2})\s*节').firstMatch(raw);
    if (single != null) {
      final n = int.parse(single.group(1)!);
      if (n >= 1) return (start: n, end: n);
    }
    return null;
  }

  static List<List<({String text, int rowspan, bool isContinuation})>>
      _expandTableMatrix(String tableHtml) {
    final rowMatches =
        RegExp(r'<tr\b[^>]*>[\s\S]*?<\/tr>', caseSensitive: false)
            .allMatches(tableHtml);
    final rows = <List<({String text, int rowspan, int colspan})>>[];
    for (final rm in rowMatches) {
      final cells = <({String text, int rowspan, int colspan})>[];
      final cellRe = RegExp(
        r'<(td|th)([^>]*)>([\s\S]*?)<\/\1>',
        caseSensitive: false,
      );
      for (final cm in cellRe.allMatches(rm.group(0)!)) {
        final attrs = cm.group(2)!;
        int span(String name) {
          final m = RegExp('$name\\s*=\\s*["\']?(\\d+)', caseSensitive: false)
              .firstMatch(attrs);
          return m != null ? int.parse(m.group(1)!) : 1;
        }

        cells.add((
          text: _linesOfCell(cm.group(3)!).join('\n'),
          rowspan: span('rowspan'),
          colspan: span('colspan'),
        ));
      }
      rows.add(cells);
    }

    final grid = <List<({String text, int rowspan, bool isContinuation})>>[];
    final pending = <String, String>{};
    for (var r = 0; r < rows.length; r++) {
      final out = <({String text, int rowspan, bool isContinuation})>[];
      var c = 0;
      void fillPending() {
        while (pending.containsKey('$r,$c')) {
          out.add((
            text: pending.remove('$r,$c')!,
            rowspan: 1,
            isContinuation: true,
          ));
          c++;
        }
      }

      fillPending();
      for (final cell in rows[r]) {
        fillPending();
        for (var k = 0; k < cell.colspan; k++) {
          out.add((
            text: cell.text,
            rowspan: cell.rowspan,
            isContinuation: k > 0,
          ));
          for (var dr = 1; dr < cell.rowspan; dr++) {
            pending['${r + dr},$c'] = cell.text;
          }
          c++;
        }
        fillPending();
      }
      grid.add(out);
    }
    return grid;
  }
}
