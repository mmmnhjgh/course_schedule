import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/ai_import_service.dart';

/// AI 一键转换导入页：复制 Prompt（可选附带教务页面文本）→ 粘贴 AI 输出 JSON → 解析返回
class AiImportPage extends StatefulWidget {
  final String? initialScheduleText;
  final int maxWeeks;
  final int maxSections;

  const AiImportPage({
    super.key,
    this.initialScheduleText,
    required this.maxWeeks,
    required this.maxSections,
  });

  @override
  State<AiImportPage> createState() => _AiImportPageState();
}

class _AiImportPageState extends State<AiImportPage> {
  final _jsonController = TextEditingController();

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _copyPrompt({bool includeSourceText = false}) async {
    final content = includeSourceText &&
            widget.initialScheduleText != null &&
            widget.initialScheduleText!.trim().isNotEmpty
        ? '${AiImportService.aiPrompt}${widget.initialScheduleText!.trim()}'
        : AiImportService.aiPrompt;
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          includeSourceText
              ? '已复制「提示词 + 教务网页文字」，去发给任意 AI 吧！'
              : '已复制转换提示词，去配合课表文字/截图发给任意 AI 吧！',
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    setState(() => _jsonController.text = text);
  }

  void _parseAndReturn() {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴 AI 返回的 JSON 内容')),
      );
      return;
    }

    try {
      final payload = AiImportService.parseAiJson(
        text,
        defaultMaxWeeks: widget.maxWeeks,
        maxSections: widget.maxSections,
      );
      if (payload.courses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON 中没有可导入的有效课程')),
        );
        return;
      }
      Navigator.of(context).pop(payload);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解析失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWebText = widget.initialScheduleText != null &&
        widget.initialScheduleText!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 一键转换课表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 1 步：复制转换提示词',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '无需配置 API Key：把提示词和你的课表截图/教务页面文字发给任意 AI（豆包、DeepSeek、ChatGPT 等）。',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasWebText)
                        FilledButton.icon(
                          onPressed: () =>
                              _copyPrompt(includeSourceText: true),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('复制提示词 + 网页文本'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _copyPrompt(includeSourceText: false),
                        icon: const Icon(Icons.copy),
                        label: Text(hasWebText ? '仅复制提示词' : '一键复制提示词'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '第 2 步：粘贴 AI 生成的 JSON',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste, size: 18),
                        label: const Text('粘贴'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _jsonController,
                    maxLines: 10,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      hintText: '支持直接粘贴 AI 回复内容（会自动剥离 ```json 代码块）...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _parseAndReturn,
                      icon: const Icon(Icons.preview),
                      label: const Text('解析并预览导入'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
