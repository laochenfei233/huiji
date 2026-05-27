import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/models/template.dart';
import 'package:yanji/screens/template_management_screen.dart';
import 'package:yanji/services/llm_service.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/services/template_service.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/utils/export_helper.dart';

class MeetingDetailScreen extends StatefulWidget {
  final int meetingId;

  const MeetingDetailScreen({super.key, required this.meetingId});

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  final StorageService _storageService = StorageService();
  final TemplateService _templateService = TemplateService();
  late Future<AppConfig> _configFuture;
  LLMService? _llmService;
  Meeting? _meeting;
  bool _isLoading = true;
  String _summary = '';
  bool _isGeneratingSummary = false;
  List<Template> _templates = [];
  String? _selectedTemplateId;
  bool _isTranscriptExpanded = false;

  @override
  void initState() {
    super.initState();
    _configFuture = ConfigLoader.loadConfig();
    _loadMeeting();
    _loadTemplates();
  }

  Future<void> _loadMeeting() async {
    try {
      final detail = await _storageService.loadMeetingDetail(widget.meetingId);
      if (detail == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _meeting = Meeting(
          id: detail.meeting.id,
          title: detail.meeting.title,
          date: detail.meeting.date,
          transcript: detail.transcript,
          summary: detail.summary,
          participants: detail.meeting.participants,
          recordingDuration: detail.meeting.recordingDuration,
          folderName: detail.meeting.folderName,
        );
        _isLoading = false;
        if (detail.summary.isNotEmpty) {
          _summary = detail.summary;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载会议详情失败: $e')),
        );
      }
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

  Future<void> _loadTemplates() async {
    try {
      final templates = await _templateService.getAllTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        if (templates.isEmpty) {
          _selectedTemplateId = null;
        } else if (_selectedTemplateId == null || !_templates.any((t) => t.id == _selectedTemplateId)) {
          _selectedTemplateId = templates.first.id;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载模板失败: $e')),
        );
      }
    }
  }

  Future<void> _generateSummary() async {
    if (_meeting == null || _selectedTemplate == null) return;

    setState(() {
      _isGeneratingSummary = true;
      _summary = '正在生成会议纪要...';
    });

    try {
      final config = await _configFuture;
      final summaryModel = config.summaryModels.first;
      _llmService = LLMService(
        baseUrl: summaryModel.url,
        apiKey: summaryModel.key,
        model: summaryModel.modelName,
      );

      // 使用选中模板的 prompt
      final templatePrompt = _selectedTemplate!.prompt
          .replaceAll('{{content}}', _meeting!.transcript ?? '');

      final summary = await _llmService!.generateSummary(
        transcript: _meeting!.transcript ?? '',
        title: _meeting!.title,
        participants: _meeting!.participants.map((p) => p.name).toList(),
        customPrompt: templatePrompt,
      );

      setState(() {
        _summary = summary;
        _isGeneratingSummary = false;
      });

      // 保存纪要到文件
      await _storageService.saveSummary(_meeting!.id!, summary);
      _meeting = Meeting(
        id: _meeting!.id,
        title: _meeting!.title,
        date: _meeting!.date,
        transcript: _meeting!.transcript,
        summary: summary,
        participants: _meeting!.participants,
        recordingDuration: _meeting!.recordingDuration,
        folderName: _meeting!.folderName,
      );
    } catch (e) {
      setState(() {
        _summary = '生成会议纪要失败: $e';
        _isGeneratingSummary = false;
      });
    }
  }

  void _showQADialog() {
    if (_meeting == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _QADialog(
        meeting: _meeting!,
        summary: _summary,
        configFuture: _configFuture,
      ),
    );
  }

  void _deleteMeeting() async {
    if (_meeting == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除会议"${_meeting!.title}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _storageService.deleteMeeting(_meeting!.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('会议已删除')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议详情'),
        actions: [
          if (_meeting != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除会议',
              onPressed: _deleteMeeting,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _meeting == null
              ? const Center(child: Text('会议不存在'))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 会议基本信息
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _meeting!.title,
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text('会议时间: ${_meeting!.date.toString()}'),
                                const SizedBox(height: 8),
                                Text('参会人员: ${_meeting!.participants.map((p) => p.name).join(', ')}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 模板选择和纪要生成
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
                                    if (_summary.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.download, size: 20),
                                        onPressed: () => ExportHelper.showExportMenu(
                                          context,
                                          title: _meeting!.title,
                                          summary: _summary,
                                          transcript: _meeting!.transcript,
                                        ),
                                        tooltip: '导出纪要',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Text('选择模板:'),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _templates.isEmpty
                                          ? const Text('加载中...')
                                          : DropdownButton<String>(
                                              value: _selectedTemplateId,
                                              isExpanded: true,
                                              items: _templates.map((template) {
                                                return DropdownMenuItem(
                                                  value: template.id,
                                                  child: Text(template.name),
                                                );
                                              }).toList(),
                                              onChanged: (String? newValue) {
                                                if (newValue != null) {
                                                  setState(() {
                                                    _selectedTemplateId = newValue;
                                                  });
                                                }
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isGeneratingSummary ? null : _generateSummary,
                                      child: _isGeneratingSummary
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Text('生成纪要'),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const TemplateManagementScreen(),
                                          ),
                                        ).then((_) => _loadTemplates());
                                      },
                                      child: const Text('管理模板'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  constraints: const BoxConstraints(minHeight: 100, maxHeight: 300),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: _summary.isEmpty
                                          ? const Text('点击"生成纪要"按钮生成会议纪要', style: TextStyle(color: Colors.grey))
                                          : MarkdownBody(data: _summary),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 智能问答按钮
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
                                leading: Icon(_isTranscriptExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more),
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
                                      child: Text(_meeting!.transcript ?? ''),
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
}

/// 问答对话框
class _QADialog extends StatefulWidget {
  final Meeting meeting;
  final String summary;
  final Future<AppConfig> configFuture;

  const _QADialog({
    required this.meeting,
    required this.summary,
    required this.configFuture,
  });

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
      final config = await widget.configFuture;
      final summaryModel = config.summaryModels.first;
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
        transcript: widget.meeting.transcript ?? '',
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
              // 标题栏
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
              // 消息列表
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
                        controller: _scrollController,
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
              // 输入框
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
