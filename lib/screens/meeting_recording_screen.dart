import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:yanji/models/meeting_session.dart';
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:yanji/services/audio_recorder_service.dart';
import 'package:yanji/services/asr_service.dart';
import 'package:yanji/services/llm_service.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/services/recording_notification_service.dart';
import 'package:yanji/screens/settings_screen.dart';
import 'package:yanji/utils/config_loader.dart';

class MeetingRecordingScreen extends StatefulWidget {
  const MeetingRecordingScreen({super.key});

  @override
  State<MeetingRecordingScreen> createState() => _MeetingRecordingScreenState();
}

class _MeetingRecordingScreenState extends State<MeetingRecordingScreen> {
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String _transcriptText = '';
  String _currentTranscription = '';
  String _connectionStatus = '';
  int _httpAsrIntervalSec = 3;
  bool _transcriptExpanded = false;
  double _transcriptPanelHeight = 120;

  AudioRecorderService? _audioRecorder;
  AsrService? _asrService;
  LLMService? _llmService;
  ASRModelConfig? _asrConfig;
  List<ASRModelConfig> _allAsrModels = [];
  StreamSubscription<Uint8List>? _audioDataSubscription;
  StreamSubscription<AsrResult>? _asrSubscription;
  StreamSubscription<AsrStatus>? _asrStatusSubscription;

  @override
  void initState() {
    super.initState();
    RecordingNotificationService.init();
    // 延迟初始化，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _httpAsrTimer?.cancel();
    _asrSubscription?.cancel();
    _asrStatusSubscription?.cancel();
    _audioDataSubscription?.cancel();
    _audioRecorder?.dispose();
    _asrService?.dispose();
    // 确保退出时关闭 wakelock
    WakelockPlus.disable();
    super.dispose();
  }

  MeetingSessionProvider get _provider =>
      Provider.of<MeetingSessionProvider>(context, listen: false);

  MeetingSession get _session => _provider.currentSession!;

  Future<void> _initializeServices() async {
    debugPrint('[Recording] _initializeServices 开始');
    try {
      final config = await ConfigLoader.loadConfig();
      _allAsrModels = config.asrModels;
      debugPrint('[Recording] ASR模型数量: ${_allAsrModels.length}, 名称: ${_allAsrModels.map((m) => m.name).toList()}');

      // 如果 session 没有指定 ASR 模型，使用第一个
      final asrModelName = _session.asrModelName.isNotEmpty
          ? _session.asrModelName
          : (config.asrModels.isNotEmpty ? config.asrModels.first.name : '');
      debugPrint('[Recording] 选择ASR模型: $asrModelName (session.asrModelName=${_session.asrModelName})');

      final asrConfig = config.asrModels.firstWhere(
        (model) => model.name == asrModelName,
        orElse: () => config.asrModels.first,
      );
      debugPrint('[Recording] ASR配置: type=${asrConfig.type}, url=${asrConfig.url}');

      _audioRecorder = AudioRecorderService();
      _asrConfig = asrConfig;
      _asrService = AsrServiceFactory.create(asrConfig);
      _httpAsrIntervalSec = asrConfig.httpAsrIntervalSec;

      if (asrConfig.type == 'http') {
        // HTTP ASR 需要使用 ASR 模型配置（如 qwen-audio-turbo），而非总结模型
        _llmService = LLMService(
          baseUrl: asrConfig.url,
          apiKey: asrConfig.key,
          model: asrConfig.modelName ?? 'qwen-audio-turbo',
          type: LLMModelType.asr,
        );
      }

      _audioDataSubscription = _audioRecorder!.audioStream.listen(
        (audioData) {
          _accumulatedAudio.addAll(audioData);
          // 防止内存无限增长：超出上限时丢弃旧数据
          if (_accumulatedAudio.length > _maxAudioBufferSize) {
            final overflow = _accumulatedAudio.length - _maxAudioBufferSize;
            _accumulatedAudio.removeRange(0, overflow);
          }
        },
        onError: (error) => _showError('音频处理错误: $error'),
      );

      // 订阅 ASR 状态变化（连接进度、错误等）
      _asrStatusSubscription = _asrService!.statusStream.listen(
        (status) {
          if (!mounted) return;
          setState(() {
            switch (status) {
              case AsrStatus.connecting:
                _connectionStatus = '正在连接 ASR 服务...';
                break;
              case AsrStatus.recognizing:
                _connectionStatus = 'ASR 已连接，实时识别中';
                break;
              case AsrStatus.error:
                _connectionStatus = 'ASR 连接失败';
                break;
              case AsrStatus.disconnected:
                _connectionStatus = 'ASR 已断开';
                break;
              case AsrStatus.stopped:
                _connectionStatus = 'ASR 已停止';
                break;
              case AsrStatus.connected:
                _connectionStatus = 'ASR 已连接';
                break;
            }
          });
        },
      );

      // 订阅 ASR 识别结果
      _asrSubscription = _asrService!.transcriptionStream.listen(
        (result) {
          if (!mounted) return;
          _onAsrResult(result);
        },
        onError: (error) => _showError('ASR错误: $error'),
      );
      debugPrint('[Recording] ASR transcriptionStream 订阅已建立, asrService=${_asrService.runtimeType}');

      if (mounted) {
        setState(() => _isInitialized = true);
      }

    } catch (e, stack) {
      debugPrint('[Recording] 初始化失败: $e\n$stack');
      _showError('初始化失败: $e');
    }
  }

  // HTTP ASR 累积音频（用于 qwen-audio-turbo 等 HTTP 模型）
  // 16kHz 16bit mono PCM: 1秒 = 32KB, 10MB ≈ 5分钟音频
  static const int _maxAudioBufferSize = 10 * 1024 * 1024;
  final List<int> _accumulatedAudio = [];
  Timer? _httpAsrTimer;

  String _lastPartial = '';

  void _onAsrResult(AsrResult result) {
    debugPrint('[Recording] _onAsrResult called: text="${result.text}", isFinal=${result.isFinal}');
    setState(() {
      if (result.isFinal) {
        final prefix = result.speaker != null ? '[${result.speaker}] ' : '';
        // 移除上一次的 partial 文本，追加 final 文本
        if (_lastPartial.isNotEmpty && _transcriptText.endsWith(_lastPartial)) {
          _transcriptText = _transcriptText.substring(0, _transcriptText.length - _lastPartial.length);
        }
        if (_transcriptText.isEmpty) {
          _transcriptText = '$prefix${result.text}';
        } else {
          _transcriptText = '$_transcriptText$prefix${result.text}';
        }
        _lastPartial = '';
        _currentTranscription = '';
      } else {
        // 移除上一次的 partial，追加新的 partial
        if (_lastPartial.isNotEmpty && _transcriptText.endsWith(_lastPartial)) {
          _transcriptText = _transcriptText.substring(0, _transcriptText.length - _lastPartial.length);
        }
        _lastPartial = result.text;
        _transcriptText = '$_transcriptText$_lastPartial';
        _currentTranscription = _lastPartial;
      }
    });

    debugPrint('[Recording] _transcriptText更新后: "${_transcriptText}" (长度: ${_transcriptText.length})');
    _provider.updateTranscript(_transcriptText);

    // 更新通知栏
    if (_isRecording) {
      RecordingNotificationService.showRecordingNotification(
        isPaused: _isPaused,
        duration: _recordingSeconds,
        transcript: _transcriptText,
      );
    }
  }

  Future<void> _processAudioDataHttp() async {
    if (_llmService == null || _accumulatedAudio.isEmpty) return;

    final audioData = Uint8List.fromList(_accumulatedAudio);
    _accumulatedAudio.clear();

    try {
      final transcription = await _llmService!.transcribeAudio(
        audioData: audioData,
        language: 'zh',
      );

      if (transcription.isNotEmpty && mounted) {
        _onAsrResult(AsrResult(text: transcription, isFinal: true));
      }
    } catch (e) {
      // 转录失败时将音频数据放回缓冲区（追加到末尾而非头部，避免 O(n) 移动）
      _accumulatedAudio.addAll(audioData);
      if (mounted) {
        _showError('转录错误: $e');
      }
    }
  }

  Future<void> _startRecording() async {
    if (_audioRecorder == null || _asrService == null) {
      _showError('服务未初始化');
      return;
    }

    // 检查 API Key 是否已配置（local_funasr/local_funasr_onnx 不需要 key）
    if (_asrConfig != null &&
        _asrConfig!.type != 'local_funasr' &&
        _asrConfig!.type != 'local_funasr_onnx' &&
        _asrConfig!.key.isEmpty) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未配置 API Key'),
            content: const Text('当前选择的 ASR 模型需要填写 API Key 才能使用，请先前往设置页面配置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
                child: const Text('跳转到设置'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      setState(() {
        _isRecording = true;
        _isProcessing = false;
        _recordingSeconds = 0;
        _accumulatedAudio.clear();
      });

      // 开始录音（仅 PCM 模式，避免双 recorder 冲突导致音频流中断）
      await _audioRecorder!.startRecording();

      // 启动 ASR 识别（连接 WebSocket / 启动 HTTP 轮询）
      await _asrService!.start(audioStream: _audioRecorder!.audioStream);

      // 保持屏幕唤醒（锁屏时继续录音）- 根据用户设置
      final prefs = await SharedPreferences.getInstance();
      final lockScreenRecording = prefs.getBool('lock_screen_recording') ?? true;
      if (lockScreenRecording) {
        await WakelockPlus.enable();
      }

      // 开始计时
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingSeconds++;
          });
          // 更新通知栏
          RecordingNotificationService.showRecordingNotification(
            isPaused: false,
            duration: _recordingSeconds,
            transcript: _transcriptText,
          );
        }
      });

      // HTTP ASR 模型：按配置间隔转录一次新增音频
      if (_llmService != null) {
        _httpAsrTimer = Timer.periodic(Duration(seconds: _httpAsrIntervalSec), (_) {
          if (_accumulatedAudio.isNotEmpty && _isRecording) {
            _processAudioDataHttp();
          }
        });
      }

      _showMessage('录音已开始');

      // 延迟检查音频流是否正常
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isRecording && _audioRecorder != null) {
          if (!_audioRecorder!.isAudioStreamAlive) {
            _showError('音频流未正常启动，请检查麦克风权限后重试');
          } else if (_accumulatedAudio.isEmpty) {
            _showError('未采集到音频数据，请检查麦克风');
          }
        }
      });

    } catch (e) {
      // ASR 连接失败时确保音频录制器也停止
      await _audioRecorder?.stopRecording();
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      _showError('开始录音失败: $e');
    }
  }

  Future<void> _pauseRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    try {
      await _audioRecorder!.pauseRecording();
      await _asrService?.stop();
      setState(() {
        _isPaused = true;
      });
      _recordingTimer?.cancel();
      // 更新通知
      RecordingNotificationService.showRecordingNotification(
        isPaused: true,
        duration: _recordingSeconds,
        transcript: _transcriptText,
      );
    } catch (e) {
      _showError('暂停录音失败: $e');
    }
  }

  Future<void> _resumeRecording() async {
    if (_audioRecorder == null || !_isPaused) return;

    try {
      setState(() {
        _isPaused = false;
      });
      await _audioRecorder!.resumeRecording();
      await _asrService!.start(audioStream: _audioRecorder!.audioStream);
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording && !_isPaused) {
          setState(() {
            _recordingSeconds++;
          });
          // 更新通知栏
          RecordingNotificationService.showRecordingNotification(
            isPaused: false,
            duration: _recordingSeconds,
            transcript: _transcriptText,
          );
        }
      });
    } catch (e) {
      _showError('恢复录音失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_audioRecorder == null) return;

    try {
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      // 停止计时器
      _recordingTimer?.cancel();
      _httpAsrTimer?.cancel();

      // 取消录音通知
      await RecordingNotificationService.cancelRecordingNotification();

      // 停止 ASR 服务
      await _asrService?.stop();

      // 停止保持唤醒
      await WakelockPlus.disable();

      // 处理剩余的音频（HTTP ASR）
      if (_llmService != null && _accumulatedAudio.isNotEmpty) {
        await _processAudioDataHttp();
      }

      // 停止录音，返回值：如果 Opus recorder 失败则返回 PCM 数据（WAV fallback）
      final fallbackPcm = await _audioRecorder!.stopRecording();

      // 保存转录和时长到 session
      debugPrint('[Recording] _stopRecording: _transcriptText="${_transcriptText}" (长度: ${_transcriptText.length})');
      await _provider.updateSession(_session.copyWith(
        originalTranscript: _transcriptText,
        recordingDuration: _recordingSeconds,
      ));

      // 自动保存（创建/更新会议记录 + 文件夹）
      await _provider.autoSave();

      // 保存音频到会议文件夹（WAV 格式）
      final meetingId = _provider.currentSession?.metadata['savedMeetingId'] as int?;
      if (meetingId != null) {
        final storage = StorageService();
        final folderPath = await storage.getMeetingFolderPath(meetingId);
        if (folderPath != null && fallbackPcm != null && fallbackPcm.isNotEmpty) {
          final audioFile = File('$folderPath/recording.wav');
          await savePcmAsWav(fallbackPcm, audioFile.path);
        }
      }

      setState(() {
        _isProcessing = false;
      });

      _showMessage('录音已完成并保存转录，转录长度: ${_transcriptText.length} 字符');

    } catch (e) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      _showError('停止录音失败: $e');
    }
  }

  Future<void> _finishRecording() async {
    if (_transcriptText.trim().isEmpty) {
      final confirmed = await _showConfirmationDialog();
      if (!confirmed) return;
    }

    if (_transcriptText.isNotEmpty) {
      await _provider.updateSession(_session.copyWith(
        originalTranscript: _transcriptText,
        recordingDuration: _recordingSeconds,
      ));
    }

    if (mounted) {
      Navigator.of(context).pushNamed('/meeting-summary');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _showError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('错误: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认完成录音'),
        content: const Text(
          '当前录音没有生成转录文本，是否确定完成录音并继续下一步？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ?? false;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _isRecording ? null : _editTitle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _session.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!_isRecording) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 16, color: Colors.grey.shade400),
              ],
            ],
          ),
        ),
        actions: [
          // ASR 模型选择
          if (_allAsrModels.length > 1)
            PopupMenuButton<String>(
              icon: Chip(
                label: Text(
                  _asrConfig?.name ?? 'ASR',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              tooltip: '切换 ASR 模型',
              onSelected: _isRecording ? null : _switchAsrModel,
              itemBuilder: (context) {
                return _allAsrModels.map((model) {
                  final isSelected = model.name == _asrConfig?.name;
                  return PopupMenuItem<String>(
                    value: model.name,
                    child: Row(
                      children: [
                        if (isSelected)
                          const Icon(Icons.check, size: 16, color: Colors.green)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(model.name)),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            tooltip: '帮助',
          ),
        ],
      ),
      body: !_isInitialized
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在初始化服务...'),
                ],
              ),
            )
          : Column(
        children: [
          _buildProgressHeader(),
          Expanded(
            child: _buildRecordingPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _transcriptText.isEmpty ? 0.3 : 0.6,
            backgroundColor: Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('录音转录'),
              Text(
                _isRecording && !_isPaused ? '录音中...' :
                _isPaused ? '已暂停' :
                _isProcessing ? '处理中...' :
                _transcriptText.isEmpty ? '待开始' : '已完成',
                style: TextStyle(
                  color: _isRecording && !_isPaused ? Colors.red :
                         _isPaused ? Colors.orange :
                         _isProcessing ? Colors.orange :
                         _transcriptText.isEmpty ? Colors.grey : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingPanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildRecordingStatus(),
              const SizedBox(height: 16),
              _buildRecordingButton(),
              const SizedBox(height: 16),
              _buildTimer(),
              const SizedBox(height: 16),
              _buildTranscriptionPanel(),
              const SizedBox(height: 12),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingStatus() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording ? Colors.red.shade100 : Colors.grey.shade100,
            border: Border.all(
              color: _isRecording ? Colors.red : Colors.grey,
              width: 3,
            ),
          ),
          child: Icon(
            _isRecording ? Icons.mic : Icons.mic_none,
            size: 40,
            color: _isRecording ? Colors.red : Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isRecording ? '正在录音...' :
          _isProcessing ? '正在处理...' :
          _transcriptText.isEmpty ? '点击开始录音' : '录音完成',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _isRecording ? Colors.red :
                   _isProcessing ? Colors.orange : Colors.green,
          ),
        ),
        // 调试信息：显示录音和 ASR 状态
        if (_isRecording) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildDebugInfo(),
          ),
        ],
      ],
    );
  }

  Widget _buildDebugInfo() {
    final wsInfo = _asrService is FunASRRealtimeService
        ? (_asrService! as FunASRRealtimeService)
        : null;
    final streamAlive = _audioRecorder?.isAudioStreamAlive ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _connectionStatus.isNotEmpty ? _connectionStatus : '状态: 等待连接...',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Row(
          children: [
            Icon(
              streamAlive ? Icons.circle : Icons.error_outline,
              size: 10,
              color: streamAlive ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 4),
            Text(
              '音频: ${(_accumulatedAudio.length / 1024).toStringAsFixed(1)} KB ${streamAlive ? "采集中" : "已中断"}',
              style: TextStyle(
                fontSize: 11,
                color: streamAlive ? Colors.grey.shade600 : Colors.red,
              ),
            ),
          ],
        ),
        if (wsInfo != null) ...[
          Text(
            'WS: ${wsInfo.url}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          Text(
            'WS: 已发送${wsInfo.audioChunksSent}块音频 (${(wsInfo.audioBytesSent / 1024).toStringAsFixed(1)} KB)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          Text(
            'WS: 收到${wsInfo.wsMessagesReceived}条消息, ${wsInfo.wsTextResultsReceived}条含文本',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  Widget _buildRecordingButton() {
    IconData icon;
    String label;
    Color color;
    VoidCallback? onPressed;

    if (_isRecording && !_isPaused) {
      icon = Icons.pause;
      label = '暂停';
      color = Colors.orange;
      onPressed = _isProcessing ? null : _pauseRecording;
    } else if (_isPaused) {
      icon = Icons.mic;
      label = '继续';
      color = Colors.green;
      onPressed = _isProcessing ? null : _resumeRecording;
    } else {
      icon = Icons.mic;
      label = '开始录音';
      color = Colors.blue;
      onPressed = _isProcessing ? null : _startRecording;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
          label: Text(label, style: const TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
        ),
        if (_isRecording || _isPaused) ...[
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _stopRecording,
            icon: const Icon(Icons.stop, size: 24),
            label: const Text('停止', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(_recordingSeconds),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptionPanel() {
    final screenHeight = MediaQuery.of(context).size.height;
    final collapsedHeight = 120.0; // 3行文本高度
    final expandedHeight = screenHeight / 2; // 半屏

    final textContent = _transcriptText.isNotEmpty
        ? _transcriptText
        : (_currentTranscription.isNotEmpty
            ? '正在处理: $_currentTranscription'
            : '开始录音后将显示实时转录内容...\n\n转录文本将自动保存到会议记录中');

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _transcriptPanelHeight -= details.delta.dy;
          _transcriptPanelHeight = _transcriptPanelHeight.clamp(collapsedHeight, expandedHeight);
        });
      },
      onVerticalDragEnd: (details) {
        // 根据速度和位置决定展开或收起
        final velocity = details.primaryVelocity ?? 0;
        setState(() {
          if (velocity.abs() > 200) {
            // 快速滑动：根据方向决定
            _transcriptExpanded = velocity < 0;
          } else {
            // 慢速拖拽：根据当前位置决定
            _transcriptExpanded = _transcriptPanelHeight > (collapsedHeight + expandedHeight) / 2;
          }
          _transcriptPanelHeight = _transcriptExpanded ? expandedHeight : collapsedHeight;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _transcriptPanelHeight,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽手柄
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.subtitles, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '转录文本',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _transcriptText.isEmpty && !_isProcessing
                  ? const Center(
                      child: Text(
                        '开始录音后将显示实时转录内容...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          height: 1.5,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Text(
                        textContent,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('上一步'),
        ),
        ElevatedButton.icon(
          onPressed: _transcriptText.isNotEmpty || _isRecording ?
                    _finishRecording : null,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('完成录音'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('录音转录说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('录音功能：'),
              SizedBox(height: 4),
              Text(
                '• 点击"开始录音"按钮开始录音\n' +
                    '• 录音过程中可以实时查看转录\n' +
                    '• 再次点击停止录音',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('ASR 语音识别：'),
              SizedBox(height: 4),
              Text(
                '• FunASR WebSocket：实时流式识别，逐句返回\n' +
                    '• HTTP ASR：每10秒批量识别一次\n' +
                    '• 支持发言人多色标注',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text('注意事项：'),
              SizedBox(height: 4),
              Text(
                '• 确保麦克风权限已开启\n' +
                    '• 录音环境应保持安静\n' +
                    '• 转录完成后将自动保存',
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

  void _editTitle() {
    final controller = TextEditingController(text: _session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改会议标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入会议标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                _provider.updateSession(_session.copyWith(title: newTitle));
                setState(() {});
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _switchAsrModel(String modelName) async {
    final config = await ConfigLoader.loadConfig();
    final newConfig = config.asrModels.firstWhere(
      (m) => m.name == modelName,
      orElse: () => config.asrModels.first,
    );

    // 如果正在录音，不能切换
    if (_isRecording) {
      _showError('录音中不能切换模型');
      return;
    }

    // 更新 session 的 ASR 模型
    await _provider.updateSession(_session.copyWith(asrModelName: modelName));

    // 重新初始化 ASR 服务
    _asrService?.dispose();
    setState(() {
      _asrConfig = newConfig;
      _httpAsrIntervalSec = newConfig.httpAsrIntervalSec;
    });

    _asrService = AsrServiceFactory.create(newConfig);
    _asrStatusSubscription?.cancel();
    _asrStatusSubscription = _asrService!.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        switch (status) {
          case AsrStatus.connecting:
            _connectionStatus = '正在连接 ASR 服务...';
            break;
          case AsrStatus.recognizing:
            _connectionStatus = 'ASR 已连接，实时识别中';
            break;
          case AsrStatus.error:
            _connectionStatus = 'ASR 连接失败';
            break;
          case AsrStatus.disconnected:
            _connectionStatus = 'ASR 已断开';
            break;
          case AsrStatus.stopped:
            _connectionStatus = 'ASR 已停止';
            break;
          case AsrStatus.connected:
            _connectionStatus = 'ASR 已连接';
            break;
        }
      });
    });

    // 重新订阅识别结果流
    _asrSubscription?.cancel();
    _asrSubscription = _asrService!.transcriptionStream.listen(
      (result) {
        if (!mounted) return;
        _onAsrResult(result);
      },
      onError: (error) => _showError('ASR错误: $error'),
    );
    debugPrint('[Recording] 切换模型后重新订阅 transcriptionStream');

    _showMessage('已切换到 ${newConfig.name}');
  }
}
