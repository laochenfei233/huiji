import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yanji/models/meeting_session.dart' as session;
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/models/template.dart';
import 'package:yanji/services/template_service.dart';

class MeetingSetupScreen extends StatefulWidget {
  const MeetingSetupScreen({super.key});

  @override
  State<MeetingSetupScreen> createState() => _MeetingSetupScreenState();
}

class _MeetingSetupScreenState extends State<MeetingSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late Future<AppConfig> _configFuture;
  
  // 表单控制器
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _participantsController = TextEditingController();
  
  // 模型选择
  String _selectedAsrModel = '';
  String _selectedSummaryModel = '';
  List<ASRModelConfig> _asrModels = [];
  List<LLMModelConfig> _llmModels = [];

  // 模板选择
  final TemplateService _templateService = TemplateService();
  List<Template> _templates = [];
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _configFuture = ConfigLoader.loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await ConfigLoader.loadConfig();
    final templates = await _templateService.getAllTemplates();
    setState(() {
      _asrModels = config.asrModels;
      _llmModels = config.llmModels;
      _templates = templates;

      // 默认选择第一个模型
      if (_asrModels.isNotEmpty) {
        _selectedAsrModel = _asrModels.first.name;
      }
      if (_llmModels.isNotEmpty) {
        _selectedSummaryModel = _llmModels.first.name;
      }
      // 默认选择第一个模板
      if (_templates.isNotEmpty) {
        _selectedTemplateId = _templates.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSetupHelp(),
          ),
        ],
      ),
      body: FutureBuilder<AppConfig>(
        future: _configFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('加载配置失败: ${snapshot.error}'),
                ],
              ),
            );
          }
          
          // 初始化配置
          if (snapshot.hasData && _asrModels.isEmpty) {
            _loadConfig();
          }
          
          return _buildSetupForm();
        },
      ),
    );
  }

  Widget _buildSetupForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 会议基本信息
            _buildSectionTitle('会议基本信息'),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '会议标题',
                hintText: '请输入会议标题',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入会议标题';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '会议描述',
                hintText: '请输入会议描述（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _participantsController,
              decoration: const InputDecoration(
                labelText: '参会人员',
                hintText: '请输入参会人员，多个用逗号分隔',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),

            // 模板选择
            _buildSectionTitle('纪要模板'),
            const SizedBox(height: 16),
            if (_templates.isEmpty)
              const Text('暂无可用模板', style: TextStyle(color: Colors.grey))
            else
              DropdownButton<String>(
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
            const SizedBox(height: 32),

            // 模型选择
            _buildSectionTitle('模型配置'),
            const SizedBox(height: 16),
            
            if (_asrModels.isEmpty)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '未找到ASR模型配置，请先在设置中配置',
                          style: TextStyle(color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildModelSelector('ASR模型', _asrModels, _selectedAsrModel, (value) {
                setState(() {
                  _selectedAsrModel = value!;
                });
              }),
            const SizedBox(height: 16),
            
            if (_llmModels.isEmpty)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '未找到总结模型配置，请先在设置中配置',
                          style: TextStyle(color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildModelSelector('总结模型', _llmModels, _selectedSummaryModel, (value) {
                setState(() {
                  _selectedSummaryModel = value!;
                });
              }),
            const SizedBox(height: 32),
            
            // 继续按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canContinue() ? _startRecording : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  '开始录音',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 进度指示器
            _buildProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildModelSelector<T>(
    String label,
    List<T> models,
    String selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: selectedValue.isNotEmpty ? selectedValue : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: models.map((model) {
        String name;
        if (model is ASRModelConfig) {
          name = model.name;
        } else if (model is LLMModelConfig) {
          name = model.name;
        } else {
          name = model.toString();
        }

        return DropdownMenuItem<String>(
          value: name,
          child: Text(name),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '请选择$label';
        }
        return null;
      },
    );
  }

  Widget _buildProgressIndicator() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '会议流程进度',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.33,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepIndicator('1', '设置', true),
                _buildStepIndicator('2', '录音', false),
                _buildStepIndicator('3', '总结', false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(String number, String label, bool isActive) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isActive 
              ? Theme.of(context).primaryColor 
              : Colors.grey.shade300,
          child: Text(
            number,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive 
                ? Theme.of(context).primaryColor 
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  bool _canContinue() {
    return _titleController.text.trim().isNotEmpty &&
           _asrModels.isNotEmpty &&
           _llmModels.isNotEmpty;
  }

  void _startRecording() async {
    if (!_formKey.currentState!.validate()) return;

    // 解析参会人员
    final participants = _participantsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((name) => Participant(
              id: name,
              name: name,
              joinTime: DateTime.now(),
            ))
        .toList();

    // 如果没有参会人员，添加默认参会人
    if (participants.isEmpty) {
      participants.add(Participant(
        id: '发言人1',
        name: '发言人1',
        joinTime: DateTime.now(),
      ));
      participants.add(Participant(
        id: '发言人2',
        name: '发言人2',
        joinTime: DateTime.now(),
      ));
    }

    // 使用 Provider 创建会议会话
    final provider = Provider.of<MeetingSessionProvider>(context, listen: false);
    await provider.createSession(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      asrModelName: _selectedAsrModel,
      summaryModelName: _selectedSummaryModel,
      templateId: _selectedTemplateId,
    );
    await provider.updateParticipants(participants);
    await provider.updateSessionState(session.MeetingSessionState.recording);

    // 导航到录音页面（Provider 会自动传递会话状态）
    if (mounted) {
      Navigator.of(context).pushNamed('/meeting-recording');
    }
  }

  void _showSetupHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('会议设置说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('会议标题：'),
              SizedBox(height: 4),
              Text(
                '• 描述本次会议的主题',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('会议描述：'),
              SizedBox(height: 4),
              Text(
                '• 可选，用于更详细地描述会议内容',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('参会人员：'),
              SizedBox(height: 4),
              Text(
                '• 输入参会人员姓名，多个用逗号分隔',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('ASR模型：'),
              SizedBox(height: 4),
              Text(
                '• 选择用于语音识别的AI模型',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('总结模型：'),
              SizedBox(height: 4),
              Text(
                '• 选择用于生成会议纪要的AI模型',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _participantsController.dispose();
    super.dispose();
  }
}