import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:yanji/services/audio_recorder_service.dart';
import 'package:yanji/services/llm_service.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _isRecording = false;
  String _transcript = '';
  String _meetingTitle = '';
  final StorageService _storageService = StorageService();
  late Future<AppConfig> _configFuture;
  final List<Participant> _participants = [
    Participant(id: '发言人1', name: '发言人1', joinTime: DateTime.now()),
    Participant(id: '发言人2', name: '发言人2', joinTime: DateTime.now()),
  ];
  String _currentSpeaker = '发言人1';
  int _wordCount = 0;

  // 防抖机制，减少界面更新频率
  Timer? _debounceTimer;
  String _pendingTranscript = '';
  bool _isTranscriptUpdateScheduled = false;

  // 新服务
  LLMService? _llmService;
  AudioRecorderService? _audioRecorder;

  // 累积音频数据
  final List<int> _accumulatedAudio = [];
  Timer? _transcriptionTimer;
  StreamSubscription<Uint8List>? _audioSubscription;

  @override
  void initState() {
    super.initState();
    _configFuture = ConfigLoader.loadConfig();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _transcriptionTimer?.cancel();
    _audioSubscription?.cancel();
    _audioRecorder?.dispose();
    super.dispose();
  }

  // 切换录音状态（开始/停止）
  void _toggleRecording() {
    if (_isTranscriptUpdateScheduled) return;
    
    setState(() {
      _isRecording = !_isRecording;
    });
    
    if (_isRecording) {
      _startRecording();
    } else {
      _stopRecording();
    }
  }

  void _startRecording() async {
    try {
      final config = await _configFuture;

      if (config.asrModels.isEmpty) {
        _showConfigurationDialog('没有找到ASR模型配置。请先在设置页面添加ASR模型配置。');
        return;
      }

      final asrConfig = config.asrModels.first;

      if (asrConfig.key.isEmpty || asrConfig.key == 'YOUR_API_KEY_HERE') {
        _showConfigurationDialog(
          'API密钥未配置或为默认值。\n\n'
          '请按以下步骤配置：\n'
          '1. 点击右上角设置按钮\n'
          '2. 编辑ASR模型\n'
          '3. 输入有效的API密钥\n'
          '4. 保存配置后重新开始录音',
        );
        return;
      }

      _llmService = LLMService(
        baseUrl: asrConfig.url,
        apiKey: asrConfig.key,
        model: asrConfig.modelName ?? asrConfig.name,
      );
      _audioRecorder = AudioRecorderService();

      setState(() {
        _transcript = '';
        _pendingTranscript = '';
        _wordCount = 0;
        _accumulatedAudio.clear();
      });

      await _audioRecorder!.startRecording();

      _audioSubscription = _audioRecorder!.audioStream.listen((audioData) {
        _accumulatedAudio.addAll(audioData);
        if (_accumulatedAudio.length > 16000 * 2 * 3) {
          _processTranscription();
        }
      });

      _transcriptionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_accumulatedAudio.isNotEmpty && _isRecording) {
          _processTranscription();
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音已启动...')),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始录音失败: $e')),
        );
        setState(() {
          _isRecording = false;
        });
      }
    }
  }

  void _stopRecording() async {
    try {
      _audioSubscription?.cancel();
      _audioSubscription = null;

      await _audioRecorder?.stopRecording();

      _transcriptionTimer?.cancel();
      _transcriptionTimer = null;

      if (_accumulatedAudio.isNotEmpty) {
        await _processTranscription();
      }

      if (_transcript.isNotEmpty) {
        await _saveMeeting();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有转录内容，未保存会议记录')),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停止录音失败: $e')),
        );
      }
    }
  }

  Future<void> _processTranscription() async {
    if (_llmService == null || _accumulatedAudio.isEmpty) {
      return;
    }

    try {
      final audioData = Uint8List.fromList(_accumulatedAudio);
      _accumulatedAudio.clear();

      final transcription = await _llmService!.transcribeAudio(
        audioData: audioData,
        language: 'zh',
      );

      if (transcription.isNotEmpty && mounted) {
        final speaker = _participants.firstWhere(
          (p) => p.id == _currentSpeaker,
          orElse: () => _participants[0],
        );

        _pendingTranscript = '[${speaker.name}] $transcription\n';
        _scheduleTranscriptUpdate();
      }
    } catch (e) {
      if (mounted) {
        _transcript += '\n[转录错误: $e]\n';
        setState(() {});
      }
    }
  }

  // 防抖机制，减少界面更新频率
  void _scheduleTranscriptUpdate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _transcript += _pendingTranscript;
          _wordCount = _transcript.split(RegExp(r'\s+')).length;
        });
      }
      _isTranscriptUpdateScheduled = false;
    });
    _isTranscriptUpdateScheduled = true;
  }

  Future<void> _saveMeeting() async {
    if (_meetingTitle.isEmpty || _transcript.isEmpty) {
      return;
    }
    
    try {
      final meeting = Meeting(
        title: _meetingTitle.isEmpty ? '会议记录' : _meetingTitle,
        date: DateTime.now(),
        transcript: _transcript,
        summary: '',
        participants: _participants,
        folderName: '',
      );
      
      await _storageService.saveMeeting(meeting);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议记录已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  /// 显示配置对话框，指导用户如何配置API密钥
  void _showConfigurationDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('🔧 需要配置ASR服务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📝 配置示例：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('• API密钥：sk-your-actual-api-key-here'),
                      Text('• 服务URL：https://dashscope.aliyuncs.com/compatible-mode/v1'),
                      Text('• 模型名称：qwen-audio-turbo'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                // 跳转到设置页面
                Navigator.pushNamed(context, '/settings');
              },
              icon: const Icon(Icons.settings),
              label: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: InputDecoration(
            hintText: '输入会议标题',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            setState(() {
              _meetingTitle = value;
            });
          },
        ),
        actions: [
          // 录音状态指示器
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isRecording ? Colors.red : Colors.grey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRecording)
                  const Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text(
                  _isRecording ? '录音中' : '已停止',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // 录音控制按钮
          IconButton(
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            onPressed: _toggleRecording,
            color: _isRecording ? Colors.red : null,
            iconSize: 32,
          ),
        ],
      ),
      
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 智能ASR服务说明
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🎤 真实麦克风录音 + 🤖 智能ASR转录服务',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 会议信息
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Text(
                      '发言人: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButton<String>(
                      value: _currentSpeaker,
                      underline: const SizedBox(),
                      items: _participants
                          .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _currentSpeaker = value;
                          });
                        }
                      },
                    ),
                    const Spacer(),
                    Text(
                      '字数: $_wordCount',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 转录文本区域
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '会议转录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12.0),
                            child: Text(
                              _transcript.isEmpty
                                  ? '🎤 点击顶部麦克风按钮开始真实录音\n\n真实音频录制特性：\n• 16kHz高质量音频采样\n• 真实麦克风数据捕获\n• 实时语音活动检测\n• 自动噪声抑制\n\n🤖 智能ASR转录特性：\n• 自动尝试多个API端点\n• 测试多种请求格式\n• 支持多种响应格式解析\n• 实时转录文本累积'
                                  : _transcript,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}