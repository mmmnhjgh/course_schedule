import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ai_import_service.dart';
import '../services/edu_parsers.dart';
import '../services/school_directory_service.dart';
import '../services/web_parser_service.dart';
import 'ai_import_page.dart';

/// 教务系统网页登录抓课页面（内置高校索引搜索 + 自动探针 + 正方 API / 强智 iframe / 通用表格 + AI 兜底）
class WebImportPage extends StatefulWidget {
  final int maxWeeks;
  final int maxSections;

  const WebImportPage({
    super.key,
    required this.maxWeeks,
    required this.maxSections,
  });

  @override
  State<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends State<WebImportPage> {
  late final WebViewController _controller;
  final _urlController = TextEditingController();
  final _schoolSearchController = TextEditingController();
  final _directory = SchoolDirectoryService();

  WebAcademicType _academicType = WebAcademicType.auto;
  int _progress = 0;
  bool _isExtracting = false;
  bool _hasNavigated = false;
  WebProbeResult? _probe;

  List<SchoolEntry> _recentSchools = [];
  List<SchoolEntry> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _hasNavigated = true;
                _probe = null;
                _urlController.text = url;
              });
            }
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _urlController.text = url);
            await _runProbe();
          },
        ),
      );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await _directory.loadRecent();
    if (mounted) setState(() => _recentSchools = recent);
  }

  Future<void> _onSearchChanged(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final list = await _directory.search(q);
    if (mounted) setState(() => _searchResults = list);
  }

  Future<void> _openSchool(SchoolEntry school) async {
    await _directory.remember(school);
    if (!mounted) return;
    setState(() {
      _urlController.text = school.url;
      if (_academicType == WebAcademicType.auto) {
        _academicType = school.academicType;
      }
    });
    _navigateToInputUrl();
  }

  void _navigateToInputUrl() {
    var url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先搜索学校或输入教务系统网址')),
      );
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    FocusScope.of(context).unfocus();
    _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _runProbe() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        WebParserService.probeJs,
      );
      final parsed = WebParserService.parseProbeResult(raw.toString());
      if (mounted) setState(() => _probe = parsed);
    } catch (_) {}
  }

  Future<({String xnm, String xqm})?> _pickZfTerm(
    ({List<String> xnm, List<String> xqm, String selXnm, String selXqm}) zf,
  ) async {
    final options = WebParserService.buildZfTermOptions(zf);
    if (options.isEmpty) return null;

    final selXnm = zf.selXnm.trim();
    final selXqm = zf.selXqm.trim();
    var selected = options.firstWhere(
      (o) => o.xnm == selXnm && o.xqm == selXqm,
      orElse: () => options.firstWhere(
        (o) => o.xnm == selXnm,
        orElse: () => options.first,
      ),
    );

    return showDialog<({String xnm, String xqm})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择正方课表学期'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, idx) {
                final opt = options[idx];
                final isSelected =
                    opt.xnm == selected.xnm && opt.xqm == selected.xqm;
                final isPageCurrent =
                    opt.xnm == selXnm && opt.xqm == selXqm;
                final label = WebParserService.formatZfTermLabel(
                  opt.xnm,
                  opt.xqm,
                );
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    isPageCurrent ? '$label（当前）' : label,
                  ),
                  selected: isSelected,
                  onTap: () => setDialogState(() => selected = opt),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('拉取课表'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractSchedule() async {
    if (!_hasNavigated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先打开学校教务系统并登录')),
      );
      return;
    }

    setState(() => _isExtracting = true);
    try {
      await _runProbe();
      final detected = _academicType == WebAcademicType.auto
          ? (EduParsers.detectSystem(_urlController.text) ??
              (_probe?.zfOptions != null
                  ? WebAcademicType.zhengfangNew
                  : _probe?.hasQzTable == true
                      ? WebAcademicType.qiangzhi
                      : WebAcademicType.genericTable))
          : _academicType;

      EduParseResult? result;

      // 1. 新版正方优先直接调用个人课表 JSON 接口
      if (detected == WebAcademicType.zhengfangNew &&
          _probe?.zfOptions != null) {
        final zf = _probe!.zfOptions!;
        final picked = await _pickZfTerm(zf);
        if (picked == null) return;
        final rawApi = await _controller.runJavaScriptReturningResult(
          WebParserService.buildZhengfangFetchJs(picked.xnm, picked.xqm),
        );
        final decoded = WebParserService.unwrapJsJson(rawApi.toString());
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          result = EduParsers.parseZhengfangKbList(
            decoded,
            maxWeeks: widget.maxWeeks,
            maxSections: widget.maxSections,
          );
        }
      }

      // 2. 强智教务优先提取主文档/iframe 内的 #kbtable
      if ((result == null || result.courses.isEmpty) &&
          (detected == WebAcademicType.qiangzhi ||
              (_probe?.hasQzTable == true))) {
        final rawQz = await _controller.runJavaScriptReturningResult(
          WebParserService.qiangzhiExtractJs,
        );
        final decoded = WebParserService.unwrapJsJson(rawQz.toString());
        if (decoded is Map<String, dynamic> &&
            decoded['ok'] == true &&
            decoded['html'] is String) {
          result = EduParsers.parseQiangzhiTableHtml(
            decoded['html'] as String,
            maxWeeks: widget.maxWeeks,
            maxSections: widget.maxSections,
          );
        }
      }

      // 3. 通用 HTML 表格兜底（支持正方 DOM 与普通表格）
      if (result == null || result.courses.isEmpty) {
        final rawHtml = await _controller.runJavaScriptReturningResult(
          WebParserService.pageHtmlJs,
        );
        final html = WebParserService.unwrapJsString(rawHtml.toString());
        final qzFallback = EduParsers.parseQiangzhiTableHtml(
          html,
          maxWeeks: widget.maxWeeks,
          maxSections: widget.maxSections,
        );
        result = qzFallback.courses.isNotEmpty
            ? qzFallback
            : EduParsers.parseGenericHtmlTable(
                html,
                maxWeeks: widget.maxWeeks,
                maxSections: widget.maxSections,
              );
      }

      if (!mounted) return;
      if (result.courses.isEmpty) {
        await _showEmptyAndAiFallback();
        return;
      }

      Navigator.of(context).pop(
        ImportPayload(
          courses: result.courses,
          warnings: result.warnings,
          sourceLabel: '教务网页 (${result.sourceTag})',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('抓取出错：$e')),
      );
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  Future<void> _showEmptyAndAiFallback() async {
    final goAi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('暂未识别到课表'),
        content: const Text(
          '请确认已登录并打开了「个人课表 / 学生课表」页面。\n\n'
          '如果该教务系统结构比较特殊，可以直接点击下方「交给 AI 转换」，'
          '软件会自动提取当前页面文字送去 AI 解析！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('留在此页'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('交给 AI 转换'),
          ),
        ],
      ),
    );
    if (goAi != true || !mounted) return;

    final rawText = await _controller.runJavaScriptReturningResult(
      WebParserService.pageTextJs,
    );
    final pageText = WebParserService.unwrapJsString(rawText.toString());
    if (!mounted) return;
    final payload = await Navigator.of(context).push<ImportPayload>(
      MaterialPageRoute(
        builder: (_) => AiImportPage(
          initialScheduleText: pageText,
          maxWeeks: widget.maxWeeks,
          maxSections: widget.maxSections,
        ),
      ),
    );
    if (payload != null && mounted) {
      Navigator.of(context).pop(payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final probeReady = _probe?.looksReady == true ||
        EduParsers.isLikelyTimetablePage(
          _academicType == WebAcademicType.auto
              ? EduParsers.detectSystem(_urlController.text)
              : _academicType,
          _urlController.text,
          _probe?.title ?? '',
        );

    final schoolList = _schoolSearchController.text.trim().isNotEmpty
        ? _searchResults
        : _recentSchools;

    return Scaffold(
      appBar: AppBar(
        title: const Text('教务网页导入'),
        actions: [
          PopupMenuButton<WebAcademicType>(
            tooltip: '切换教务解析模式',
            initialValue: _academicType,
            onSelected: (type) => setState(() => _academicType = type),
            itemBuilder: (context) => WebAcademicType.values
                .map(
                  (t) => CheckedPopupMenuItem(
                    value: t,
                    checked: t == _academicType,
                    child: Text(t.label),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: '后退',
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      await _controller.goBack();
                    }
                  },
                ),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _controller.reload(),
                ),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _navigateToInputUrl(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '输入教务系统网址...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _navigateToInputUrl,
                  child: const Text('前往'),
                ),
              ],
            ),
          ),
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          Expanded(
            child: _hasNavigated
                ? WebViewWidget(controller: _controller)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _schoolSearchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: '搜索高校名称直达教务网址（如：浙江大学、清华大学）',
                          border: const OutlineInputBorder(),
                          suffixIcon: _schoolSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _schoolSearchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (schoolList.isNotEmpty) ...[
                        Text(
                          _schoolSearchController.text.trim().isNotEmpty
                              ? '匹配学校'
                              : '最近使用',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        ...schoolList.map(
                          (s) => ListTile(
                            leading: const Icon(Icons.school_outlined),
                            title: Text(s.name),
                            subtitle: Text(
                              s.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Chip(label: Text(s.systemLabel)),
                            onTap: () => _openSchool(s),
                          ),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.public_outlined,
                                size: 56,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '在上方搜索学校或输入教务网址打开，登录后进入「个人课表」页，点击右下角按钮即可导入。',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _hasNavigated
          ? FloatingActionButton.extended(
              onPressed: _isExtracting ? null : _extractSchedule,
              backgroundColor:
                  probeReady ? colorScheme.primary : colorScheme.secondaryContainer,
              foregroundColor:
                  probeReady ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
              icon: _isExtracting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(probeReady ? Icons.download_done : Icons.search),
              label: Text(
                _isExtracting
                    ? '识别中...'
                    : (probeReady ? '检测到课表，点此导入' : '识别当前页课表'),
              ),
            )
          : null,
    );
  }
}
