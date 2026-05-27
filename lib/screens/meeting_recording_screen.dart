import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:yanji/models/meeting_session.dart';
import 'package:yanji/providers/meeting_session_provider.dart';
import 'package:yanji/services/audio_recorder_service.dart';
import 'package:yanji/services/asr_service.dart';
import 'package:yanji/services/llm_service.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/utils/config_loader.dart';

class MeetingRecordingScreen extends StatefulWidget {
  const MeetingRecordingScreen({super.key});

  @override
  State<MeetingRecordingScreen> createState() => _MeetingRecordingScreenState();
}

class _MeetingRecordingScreenState extends State<MeetingRecordingScreen> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String _transcriptText = '';
  String _currentTranscription = '';
  String _connectionStatus = '';
  bool _transcriptExpanded = false;
  AnimationController? _transcriptAnimController;
  Animation<double>? _transcriptHeightAnimation;
  int _httpAsrIntervalSec = 3; // HTTP ASR 发送间隔

  AudioRecorderService? _audioRecorder;
  AsrService? _asrService;
  LLMService? _llmService;
  StreamSubscription<Uint8List>? _audioDataSubscription;
  StreamSubscription<AsrResult>? _asrSubscription;
  StreamSubscription<AsrStatus>? _asrStatusSubscription;

  @override
  void initState() {
    super.initState();
    _transcriptAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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
    _transcriptAnimController?.dispose();
    super.dispose();
  }

  MeetingSessionProvider get _provider =>
      Provider.of<MeetingSessionProvider>(context, listen: false);

  MeetingSession get _session => _provider.currentSession!;

  Future<void> _initializeServices() async {
    try {
      final config = await ConfigLoader.loadConfig();
      final asrConfig = config.asrModels.firstWhere(
        (model) => model.name == _session.asrModelName,
        orElse: () => config.asrModels.first,
      );
      final llmConfig = config.llmModels.firstWhere(
        (model) => model.name == _session.summaryModelName,
        orElse: () => config.llmModels.first,
      );

      _audioRecorder = AudioRecorderService();
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

      if (mounted) {
        setState(() => _isInitialized = true);
      }

    } catch (e) {
      _showError('初始化失败: $e');
    }
  }

  // HTTP ASR 累积音频（用于 qwen-audio-turbo 等 HTTP 模型）
  final List<int> _accumulatedAudio = [];
  Timer? _httpAsrTimer;

  String _lastPartial = '';

  void _onAsrResult(AsrResult result) {
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

    _provider.updateTranscript(_transcriptText);
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
      _accumulatedAudio.insertAll(0, audioData);
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

    try {
      setState(() {
        _isRecording = true;
        _isProcessing = false;
        _recordingSeconds = 0;
        _accumulatedAudio.clear();
      });

      // 开始录音（尝试同时写 Opus 文件到临时路径，失败则 fallback WAV）
      final tempDir = await getTemporaryDirectory();
      final tempOpusPath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.opus';
      await _audioRecorder!.startRecording(opusOutputPath: tempOpusPath);

      // 启动 ASR 识别（连接 WebSocket / 启动 HTTP 轮询）
      await _asrService!.start(audioStream: _audioRecorder!.audioStream);

      // 开始计时
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingSeconds++;
          });
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

      // 停止 ASR 服务
      await _asrService?.stop();

      // 处理剩余的音频（HTTP ASR）
      if (_llmService != null && _accumulatedAudio.isNotEmpty) {
        await _processAudioDataHttp();
      }

      // 停止录音，返回值：如果 Opus recorder 失败则返回 PCM 数据（WAV fallback）
      final fallbackPcm = await _audioRecorder!.stopRecording();

      // 保存转录和时长到 session
      await _provider.updateSession(_session.copyWith(
        originalTranscript: _transcriptText,
        recordingDuration: _recordingSeconds,
      ));

      // 自动保存（创建/更新会议记录 + 文件夹）
      await _provider.autoSave();

      // 保存音频到会议文件夹
      final meetingId = _provider.currentSession?.metadata['savedMeetingId'] as int?;
      if (meetingId != null) {
        final storage = StorageService();
        final folderPath = await storage.getMeetingFolderPath(meetingId);
        if (folderPath != null) {
          if (_audioRecorder!.isOpusRecording) {
            // Opus recorder 已写到临时路径，移动到会议文件夹
            final tempOpus = _audioRecorder!.opusOutputPath;
            if (tempOpus != null && File(tempOpus).existsSync()) {
              await File(tempOpus).copy('$folderPath/recording.opus');
              await File(tempOpus).delete();
            }
          } else if (fallbackPcm != null && fallbackPcm.isNotEmpty) {
            // WAV fallback：将累积的 PCM 保存为 WAV
            final audioFile = File('$folderPath/recording.wav');
            await savePcmAsWav(fallbackPcm, audioFile.path);
          }
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
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
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
            value: 2/3,
            backgroundColor: Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('第2步：录音转录'),
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
        if (false && _currentTranscription.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              '实时转录: $_currentTranscription',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDebugInfo() {
    final wsInfo = _asrService is FunASRRealtimeService
        ? (_asrService! as FunASRRealtimeService)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _connectionStatus.isNotEmpty ? _connectionStatus : '状态: 等待连接...',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          '音频: ${(_accumulatedAudio.length / 1024).toStringAsFixed(1)} KB 已采集',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
    final maxTranscriptHeight = screenHeight / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算文本自然高度
        final textContent = _transcriptText.isNotEmpty
            ? _transcriptText
            : (_currentTranscription.isNotEmpty
                ? '正在处理: $_currentTranscription'
                : '开始录音后将显示实时转录内容...\n\n转录文本将自动保存到会议记录中');
        final textPainter = TextPainter(
          text: TextSpan(
            text: textContent,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          maxLines: null,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth - 24);
        final naturalHeight = textPainter.height + 24; // + padding

        final targetHeight = _transcriptExpanded
            ? maxTranscriptHeight
            : naturalHeight.clamp(80.0, maxTranscriptHeight);

        // 首次设置动画
        if (_transcriptHeightAnimation == null) {
          _transcriptHeightAnimation = Tween<double>(
            begin: targetHeight,
            end: targetHeight,
          ).animate(CurvedAnimation(
            parent: _transcriptAnimController!,
            curve: Curves.easeInOut,
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onVerticalDragEnd: _transcriptText.isNotEmpty
                  ? (details) {
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! < -50) {
                          _expandTranscript(maxTranscriptHeight);
                        } else if (details.primaryVelocity! > 50) {
                          _collapseTranscript(naturalHeight);
                        }
                      }
                    }
                  : null,
              child: AnimatedBuilder(
                animation: _transcriptAnimController!,
                builder: (context, child) {
                  final height = _transcriptHeightAnimation?.value ?? targetHeight;
                  return Container(
                    height: height,
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
                            if (_transcriptText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(
                                _transcriptExpanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up,
                                size: 20,
                                color: Colors.grey,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _transcriptText.isEmpty && !_isProcessing
                              ? const Center(
                                  child: Text(
                                    '开始录音后将显示实时转录内容...\n\n转录文本将自动保存到会议记录中',
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
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _expandTranscript(double maxHeight) {
    if (_transcriptExpanded) return;
    final currentHeight = _transcriptHeightAnimation?.value ?? 80.0;
    _transcriptHeightAnimation = Tween<double>(
      begin: currentHeight,
      end: maxHeight,
    ).animate(CurvedAnimation(
      parent: _transcriptAnimController!,
      curve: Curves.easeOutCubic,
    ));
    _transcriptAnimController!.forward(from: 0);
    setState(() => _transcriptExpanded = true);
  }

  void _collapseTranscript(double naturalHeight) {
    if (!_transcriptExpanded) return;
    final currentHeight = _transcriptHeightAnimation?.value ?? naturalHeight;
    _transcriptHeightAnimation = Tween<double>(
      begin: currentHeight,
      end: naturalHeight,
    ).animate(CurvedAnimation(
      parent: _transcriptAnimController!,
      curve: Curves.easeInCubic,
    ));
    _transcriptAnimController!.forward(from: 0);
    setState(() => _transcriptExpanded = false);
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
}
