import 'dart:convert';

import 'edu_parsers.dart';

/// 教务网页探针结果
class WebProbeResult {
  final String url;
  final String title;
  final bool hasTable;
  final ({List<String> xnm, List<String> xqm, String selXnm, String selXqm})?
      zfOptions;
  final bool hasQzTable;

  const WebProbeResult({
    required this.url,
    required this.title,
    required this.hasTable,
    this.zfOptions,
    required this.hasQzTable,
  });

  bool get looksReady => hasTable || zfOptions != null || hasQzTable;
}

/// 负责生成教务网页探针、正方 API / 强智 iframe / 通用 HTML 抓取脚本
class WebParserService {
  /// 1. 探测页面：找课表表格、新版正方学年学期下拉、强智同源 iframe 课表
  static const String probeJs = '''
(function() {
  var r = { url: location.href, title: document.title || '', table: false, zf: null, qz: false };
  var ts = document.getElementsByTagName('table');
  for (var i = 0; i < ts.length; i++) {
    if (/星期|周一|Monday|Mon\\b/i.test(ts[i].innerText || '')) { r.table = true; break; }
  }
  var xn = document.getElementById('xnm'), xq = document.getElementById('xqm');
  if (xn && xq && xn.tagName === 'SELECT' && xq.tagName === 'SELECT') {
    var opt = function(sel) {
      var out = [];
      for (var i = 0; i < sel.options.length; i++) {
        var o = sel.options[i];
        var v = String(o.value || '').trim();
        var t = String(o.text || '').trim();
        if (!v || v === 'all' || /全部|请选择/.test(t)) continue;
        out.push(v);
      }
      return out;
    };
    r.zf = { xnm: opt(xn), xqm: opt(xq), selXnm: String(xn.value || '').trim(), selXqm: String(xq.value || '').trim() };
  }
  var qzHit = function(d) {
    if (!d || !d.querySelector) return false;
    if (d.querySelector('table#kbtable')) return true;
    var qts = d.getElementsByTagName('table');
    for (var j = 0; j < qts.length; j++) {
      if (qts[j].querySelector('.kbcontent') || qts[j].querySelector('.kbcontent1')) return true;
    }
    return false;
  };
  if (qzHit(document)) r.qz = true;
  else {
    var fs = document.querySelectorAll('iframe,frame');
    for (var k = 0; k < fs.length; k++) {
      try {
        var d = fs[k].contentDocument;
        if (d && qzHit(d)) { r.qz = true; break; }
      } catch (e) {}
    }
  }
  return JSON.stringify(r);
})();
''';

  /// 2. 新版正方专用：复用当前页面登录 Cookie 请求个人课表 JSON 接口（同步 XHR 兼容所有 WebView）
  static String buildZhengfangFetchJs(String xnm, String xqm) {
    final body =
        'xnm=${Uri.encodeComponent(xnm)}&xqm=${Uri.encodeComponent(xqm)}';
    return '''
(function() {
  try {
    var p = location.pathname;
    var kbcxIdx = p.indexOf('/kbcx/');
    var base = kbcxIdx >= 0 ? p.slice(0, kbcxIdx) : (p.indexOf('/jwglxt/') >= 0 ? p.slice(0, p.indexOf('/jwglxt/')) + '/jwglxt' : '');
    var gm = (location.search || '').match(/[?&](gnmkdm=[^&]+)/);
    var gnmk = gm ? gm[1] : 'gnmkdm=N253508';
    var xhr = new XMLHttpRequest();
    xhr.open('POST', base + '/kbcx/xskbcx_cxXsgrkb.html?' + gnmk, false);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.send(${jsonEncode(body)});
    if (xhr.status < 200 || xhr.status >= 300) {
      return JSON.stringify({ ok: false, error: 'HTTP ' + xhr.status });
    }
    var j = JSON.parse(xhr.responseText || '{}');
    var list = (j && j.kbList) || [];
    var slim = list.map(function(c) {
      return { kcmc: c.kcmc, xm: c.xm, cdmc: c.cdmc, xqj: c.xqj, jcs: c.jcs, zcd: c.zcd };
    });
    return JSON.stringify({ ok: true, kbList: slim });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String((e && e.message) || e) });
  }
})();
''';
  }

  /// 3. 强智教务专用：在主文档与同源 iframe 中提取 #kbtable；若周次被筛选则重抓完整表
  static const String qiangzhiExtractJs = '''
(function() {
  var docs = [document];
  var fs = document.querySelectorAll('iframe,frame');
  for (var i = 0; i < fs.length; i++) {
    try { var d = fs[i].contentDocument; if (d && d.location) docs.push(d); } catch (e) {}
  }
  var findTable = function(d) {
    var t = d.querySelector('table#kbtable');
    if (t) return t;
    var ts = d.getElementsByTagName('table');
    for (var j = 0; j < ts.length; j++) {
      if (ts[j].querySelector('.kbcontent') || ts[j].querySelector('.kbcontent1')) return ts[j];
    }
    return null;
  };
  var doc = null, tb = null;
  for (var k = 0; k < docs.length; k++) {
    tb = findTable(docs[k]);
    if (tb) { doc = docs[k]; break; }
  }
  if (!doc || !tb) return JSON.stringify({ ok: false, error: 'NO_TABLE' });

  var zc = doc.getElementById ? doc.getElementById('zc') : null;
  var sel = doc.getElementById ? doc.getElementById('xnxq01id') : null;
  if (zc && zc.value) {
    try {
      var kbj = doc.getElementById('kbjcmsid');
      var qs = 'zc=&demo=&xnxq01id=' + encodeURIComponent(sel ? sel.value : '') +
        '&kbjcmsid=' + encodeURIComponent(kbj ? kbj.value : '') + '&sfFD=1';
      var xhr = new XMLHttpRequest();
      xhr.open('POST', doc.location.href, false);
      xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
      xhr.send(qs);
      if (xhr.status >= 200 && xhr.status < 300) {
        var nd = new DOMParser().parseFromString(xhr.responseText, 'text/html');
        var nt = findTable(nd);
        if (nt) tb = nt;
      }
    } catch (e) {}
  }
  return JSON.stringify({ ok: true, html: tb.outerHTML });
})();
''';

  /// 4. 提取主文档及同源 iframe 的 HTML（供通用表格解析）
  static const String pageHtmlJs = '''
(function() {
  var html = document.documentElement ? document.documentElement.outerHTML : '';
  var fs = document.querySelectorAll('iframe,frame');
  for (var i = 0; i < fs.length; i++) {
    try {
      var d = fs[i].contentDocument;
      if (d && d.documentElement) html += '\\n' + d.documentElement.outerHTML;
    } catch (e) {}
  }
  return html;
})();
''';

  /// 5. 提取页面可见纯文本（供抓课失败时转交 AI 一键转换）
  static const String pageTextJs = '''
(function() {
  var parts = [];
  if (document.body && document.body.innerText) parts.push(document.body.innerText);
  var fs = document.querySelectorAll('iframe,frame');
  for (var i = 0; i < fs.length; i++) {
    try {
      var d = fs[i].contentDocument;
      if (d && d.body && d.body.innerText) parts.push(d.body.innerText);
    } catch (e) {}
  }
  return parts.join('\\n\\n');
})();
''';

  static WebProbeResult? parseProbeResult(String raw) {
    final decoded = unwrapJsJson(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final rawZf = decoded['zf'];
    ({List<String> xnm, List<String> xqm, String selXnm, String selXqm})? zf;
    if (rawZf is Map<String, dynamic>) {
      zf = (
        xnm: (rawZf['xnm'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        xqm: (rawZf['xqm'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        selXnm: rawZf['selXnm']?.toString() ?? '',
        selXqm: rawZf['selXqm']?.toString() ?? '',
      );
    }
    return WebProbeResult(
      url: decoded['url']?.toString() ?? '',
      title: decoded['title']?.toString() ?? '',
      hasTable: decoded['table'] == true,
      zfOptions: zf,
      hasQzTable: decoded['qz'] == true,
    );
  }

  /// 根据网页探测到的正方学年/学期列表生成合理顺序的候选选项，优先围绕当前选中/当前年份
  static List<({String xnm, String xqm})> buildZfTermOptions(
    ({List<String> xnm, List<String> xqm, String selXnm, String selXqm}) zf, {
    int? referenceYear,
  }) {
    final nowYear = referenceYear ?? DateTime.now().year;
    final selXnm = zf.selXnm.trim();
    final selXqm = zf.selXqm.trim();
    final selYear = int.tryParse(selXnm);
    final maxYear = selYear != null && selYear > nowYear ? selYear : nowYear;

    final allYears = zf.xnm
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (selXnm.isNotEmpty && !allYears.contains(selXnm)) {
      allYears.add(selXnm);
    }
    allYears.sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return bi.compareTo(ai);
      return b.compareTo(a);
    });

    var filteredYears = allYears.where((y) {
      final yi = int.tryParse(y);
      if (yi == null) return true;
      return yi <= maxYear;
    }).toList();
    if (filteredYears.isEmpty) {
      filteredYears = allYears;
    }
    final pickedYears = filteredYears.take(3).toList();
    if (selXnm.isNotEmpty && !pickedYears.contains(selXnm)) {
      pickedYears.insert(0, selXnm);
    }

    const order = ['3', '12', '16'];
    int termRank(String q) {
      final idx = order.indexOf(q);
      return idx >= 0 ? idx : 99;
    }

    final terms = zf.xqm
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != 'all')
        .toSet()
        .toList();
    if (selXqm.isNotEmpty && selXqm != 'all' && !terms.contains(selXqm)) {
      terms.add(selXqm);
    }
    terms.sort((a, b) => termRank(a).compareTo(termRank(b)));

    final options = <({String xnm, String xqm})>[];
    for (final y in pickedYears) {
      for (final q in terms) {
        options.add((xnm: y, xqm: q));
      }
    }
    return options;
  }

  /// 格式化正方学年学期标签，例如 "2026" + "3" -> "2026–2027 学年 第 1 学期"
  static String formatZfTermLabel(String xnm, String xqm) {
    final cleanXnm = xnm.trim();
    final cleanXqm = xqm.trim();
    final year = int.tryParse(cleanXnm);
    final term = switch (cleanXqm) {
      '3' => '第 1 学期',
      '12' => '第 2 学期',
      '16' => '第 3 学期',
      '' => '默认学期',
      _ => '学期 $cleanXqm',
    };
    return year != null ? '$year–${year + 1} 学年 $term' : '$cleanXnm $term';
  }

  static dynamic unwrapJsJson(String raw) {
    dynamic current = raw.trim();
    for (var i = 0; i < 2; i++) {
      if (current is String) {
        try {
          current = jsonDecode(current);
        } catch (_) {
          break;
        }
      }
    }
    return current;
  }

  /// 解包 `pageHtmlJs` / `pageTextJs` 返回的字符串
  static String unwrapJsString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return raw;
  }

  /// 兼容旧版直接解析接口调用
  static EduParseResult parseExtractedPayload(
    String rawResult, {
    int maxWeeks = 20,
    int maxSections = 12,
  }) {
    final decoded = unwrapJsJson(rawResult);
    if (decoded is Map<String, dynamic> && decoded['kbList'] is List) {
      return EduParsers.parseZhengfangKbList(
        decoded,
        maxWeeks: maxWeeks,
        maxSections: maxSections,
      );
    }
    return const EduParseResult(
      courses: [],
      warnings: ['未能解析返回结构'],
    );
  }

  static List<int> parseWeeksExpression(String expr, {int maxWeeks = 25}) =>
      EduParsers.parseWeeksExpression(expr, maxWeeks: maxWeeks);
}
