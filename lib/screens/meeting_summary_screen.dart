import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:yanji/models/meeting_session.dart';
import 'package:yanji/models/template.dart';
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:yanji/services/llm_service.dart';
import 'package:yanji/services/template_service.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/utils/export_helper.dart';

class MeetingSummaryScreen extends StatefulWidget {
  const MeetingSummaryScreen({super.key});

  @override
  State<MeetingSummaryScreen> createState() => _MeetingSummaryScreenState();
}

class _MeetingSummaryScreenState extends State<MeetingSummaryScreen> {
  bool _isGenerating = false;
  String _summaryText = '';
  bool _isTranscriptExpanded = false;
  List<Template> _templates = [];
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _initializeLLMService();
  }

  MeetingSession get _session =>
      Provider.of<MeetingSessionProvider>(context, listen: false).currentSession!;

  Future<void> _loadTemplates() async {
    try {
      final templates = await TemplateService().getAllTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        final sessionTemplateId = _session.metadata['templateId'] as String?;
        if (sessionTemplateId != null && templates.any((t) => t.id == sessionTemplateId)) {
          _selectedTemplateId = sessionTemplateId;
        } else if (templates.isNotEmpty) {
          _selectedTemplateId = templates.first.id;
        }
      });
    } catch (e) {
      // ignore
    }
  }

  Template? get _selectedTemplate {
    if (_selectedTemplateId == null || _templates.isEmpty) return null;
    try {
      return _templates.firstWhere((t) => t.id == _selectedTemplateId);
    } catch (_) {
      return _templates.isNotEmpty ? _templates.first : null;
    }
  }

  Future<void> _initializeLLMService() async {
    if (_session.originalTranscript.isNotEmpty && _session.summaryText == null) {
      _generateSummary();
    } else if (_session.summaryText != null) {
      setState(() {
        _summaryText = _session.summaryText!;
      });
    }
  }

  Future<void> _generateSummary() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final config = await ConfigLoader.loadConfig();
      final summaryConfig = config.llmModels.firstWhere(
        (model) => model.name == _session.summaryModelName,
        orElse: () => config.llmModels.first,
      );
      final llmService = LLMServiceFactory.create(summaryConfig);

      String? customPrompt;
      final templateId = _selectedTemplateId ?? (_session.metadata['templateId'] as String?);
      if (templateId != null && templateId.isNotEmpty) {
        final templateService = TemplateService();
        final template = await templateService.getTemplateById(templateId);
        if (template != null) {
          customPrompt = template.prompt.replaceAll('{{content}}', _session.originalTranscript);
        }
      }

      final summary = await llmService.generateSummary(
        transcript: _session.originalTranscript,
        title: _session.title,
        participants: _session.participants.map((p) => p.name).toList(),
        customPrompt: customPrompt,
      );

      setState(() {
        _summaryText = summary;
      });

      final provider = Provider.of<MeetingSessionProvider>(context, listen: false);
      await provider.updateSummary(summary);
      await provider.autoSave();

      _showMessage('会议纪要生成成功');
    } catch (e) {
      _showError('生成纪要失败: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _saveAndFinish() async {
    final provider = Provider.of<MeetingSessionProvider>(context, listen: false);
    await provider.completeSession();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('错误: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<MeetingSessionProvider>(context).currentSession;
    final title = session?.title ?? '会议总结';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAndFinish,
            tooltip: '保存会议结果',
          ),
          if (_summaryText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => ExportHelper.showExportMenu(
                context,
                title: title,
                summary: _summaryText,
                transcript: _session.originalTranscript,
              ),
              tooltip: '导出纪要',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isGenerating ? null : _generateSummary,
            tooltip: '重新生成纪要',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 会议信息卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_session.participants.isNotEmpty)
                        Text('参会人员: ${_session.participants.map((p) => p.name).join(', ')}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 会议纪要卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '会议纪要',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_summaryText.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.download, size: 20),
                              onPressed: () => ExportHelper.showExportMenu(
                                context,
                                title: title,
                                summary: _summaryText,
                                transcript: _session.originalTranscript,
                              ),
                              tooltip: '导出纪要',
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 模板选择
                      Row(
                        children: [
                          const Text('模板:'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _templates.isEmpty
                                ? const Text('加载中...', style: TextStyle(color: Colors.grey))
                                : DropdownButton<String>(
                                    value: _selectedTemplateId,
                                    isExpanded: true,
                                    items: _templates.map((t) {
                                      return DropdownMenuItem(value: t.id, child: Text(t.name));
                                    }).toList(),
                                    onChanged: _isGenerating
                                        ? null
                                        : (v) {
                                            if (v != null) setState(() => _selectedTemplateId = v);
                                          },
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 纪要内容
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 100),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: _isGenerating
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text('正在生成会议纪要...'),
                                    ],
                                  ),
                                ),
                              )
                            : _summaryText.isEmpty
                                ? Column(
                                    children: [
                                      const SizedBox(height: 16),
                                      const Icon(Icons.auto_awesome, size: 48, color: Colors.grey),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '点击下方按钮生成会议纪要',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _generateSummary,
                                        icon: const Icon(Icons.auto_awesome, size: 16),
                                        label: const Text('生成纪要'),
                                      ),
                                    ],
                                  )
                                : MarkdownBody(
                                    data: _summaryText,
                                    styleSheet: MarkdownStyleSheet(
                                      p: const TextStyle(fontSize: 14, height: 1.5),
                                      strong: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 智能问答卡片
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text(
                    '智能问答',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('可以询问关于会议内容的任何问题'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: _showQADialog,
                ),
              ),
              const SizedBox(height: 16),

              // 会议原文（可折叠）
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(_isTranscriptExpanded ? Icons.expand_less : Icons.expand_more),
                      title: const Text(
                        '会议原文',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        setState(() {
                          _isTranscriptExpanded = !_isTranscriptExpanded;
                        });
                      },
                    ),
                    if (_isTranscriptExpanded)
                      Container(
                        height: 300,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _session.originalTranscript.isEmpty
                                  ? '暂无转录文本'
                                  : _session.originalTranscript,
                              style: const TextStyle(fontSize: 14, height: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQADialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _QADialog(
        transcript: _session.originalTranscript,
        summary: _summaryText,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// 问答对话框
class _QADialog extends StatefulWidget {
  final String transcript;
  final String summary;

  const _QADialog({required this.transcript, required this.summary});

  @override
  State<_QADialog> createState() => _QADialogState();
}

class _QADialogState extends State<_QADialog> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isGenerating = false;
  LLMService? _llmService;

  @override
  void initState() {
    super.initState();
    _initLLM();
  }

  Future<void> _initLLM() async {
    try {
      final config = await ConfigLoader.loadConfig();
      final summaryModel = config.llmModels.first;
      _llmService = LLMService(
        baseUrl: summaryModel.url,
        apiKey: summaryModel.key,
        model: summaryModel.modelName,
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> _askQuestion() async {
    if (_questionController.text.isEmpty || _llmService == null) return;

    final question = _questionController.text.trim();
    _questionController.clear();

    setState(() {
      _messages.add(_ChatMessage(message: question, isUser: true));
      _isGenerating = true;
    });

    _scrollToBottom();

    try {
      final answer = await _llmService!.askQuestion(
        question: question,
        transcript: widget.transcript,
        summary: widget.summary.isNotEmpty ? widget.summary : null,
      );

      setState(() {
        _messages.add(_ChatMessage(message: answer, isUser: false));
        _isGenerating = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(message: '回答失败: $e', isUser: false));
        _isGenerating = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '智能问答',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.question_answer, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                '询问关于会议内容的任何问题',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildSuggestionChip('主要结论是什么？'),
                                  _buildSuggestionChip('有哪些待办事项？'),
                                  _buildSuggestionChip('谁负责哪些任务？'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isGenerating ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return _buildTypingIndicator();
                          }
                          final msg = _messages[index];
                          return _buildMessageBubble(msg);
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          hintText: '输入你的问题...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _askQuestion(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isGenerating ? null : _askQuestion,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      onPressed: () {
        _questionController.text = text;
        _askQuestion();
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? Text(msg.message)
            : MarkdownBody(
                data: msg.message,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                ),
              ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            Text('思考中...', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String message;
  final bool isUser;

  _ChatMessage({required this.message, required this.isUser});
}
