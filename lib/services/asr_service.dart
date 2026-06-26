import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/models/ai_model.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// ASR 识别状态
enum AsrStatus {
  disconnected,
  connecting,
  connected,
  recognizing,
  stopped,
  error,
}

/// ASR 识别结果
class AsrResult {
  final String text;
  final bool isFinal; // false=中间结果, true=最终结果
  final String? speaker;

  AsrResult({
    required this.text,
    this.isFinal = false,
    this.speaker,
  });
}

/// ASR 服务抽象接口
abstract class AsrService {
  /// 转录结果流：实时返回识别文本
  Stream<AsrResult> get transcriptionStream;

  /// 状态流
  Stream<AsrStatus> get statusStream;

  /// 当前状态
  AsrStatus get status;

  /// 启动识别，订阅音频流并发送到 ASR 服务
  Future<void> start({required Stream<Uint8List> audioStream});

  /// 停止识别
  Future<void> stop();

  /// 释放资源
  void dispose();
}

/// ASR 服务公共实现 — 消除各实现类的重复代码
mixin AsrServiceMixin on AsrService {
  final StreamController<AsrResult> _transcriptionController =
      StreamController<AsrResult>.broadcast();
  final StreamController<AsrStatus> _statusController =
      StreamController<AsrStatus>.broadcast();
  AsrStatus _status = AsrStatus.disconnected;

  @override
  Stream<AsrResult> get transcriptionStream => _transcriptionController.stream;

  @override
  Stream<AsrStatus> get statusStream => _statusController.stream;

  @override
  AsrStatus get status => _status;

  void _updateStatus(AsrStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) _statusController.add(newStatus);
  }

  /// 子类 dispose 末尾调用此方法关闭 controller
  void disposeControllers() {
    _transcriptionController.close();
    _statusController.close();
  }
}

/// 空实现（无 ASR 配置时使用）
class NoOpAsrService extends AsrService with AsrServiceMixin {
  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    _updateStatus(AsrStatus.recognizing);
  }

  @override
  Future<void> stop() async {
    _updateStatus(AsrStatus.stopped);
  }

  @override
  void dispose() {
    disposeControllers();
  }
}

/// DashScope 百炼实时语音识别 WebSocket 实现
class FunASRRealtimeService extends AsrService with AsrServiceMixin {
  final String url;
  final String? apiKey;
  final String? modelName;
  final Map<String, dynamic> _extraParams;

  WebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  String? _currentTaskId;
  bool _taskStarted = false;

  static const _connectionTimeout = Duration(seconds: 10);
  final List<Uint8List> _audioBuffer = [];
  static const int _maxBufferSize = 200;
  bool _isFlushing = false;

  int audioBytesSent = 0;
  int audioChunksSent = 0;
  int wsMessagesReceived = 0;
  int wsTextResultsReceived = 0;

  FunASRRealtimeService({
    required this.url,
    this.apiKey,
    this.modelName,
    Map<String, dynamic>? extraParams,
  }) : _extraParams = extraParams ?? {};

  Uri _buildWsUri() {
    if (!kIsWeb && apiKey != null && apiKey!.isNotEmpty) {
      return Uri.parse('wss://dashscope.aliyuncs.com/api-ws/v1/inference');
    }
    var wsUrl = url.trim();
    if (wsUrl.startsWith('https://')) {
      wsUrl = 'wss://${wsUrl.substring(8)}';
    } else if (wsUrl.startsWith('http://')) {
      wsUrl = 'ws://${wsUrl.substring(7)}';
    }
    if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
      wsUrl = 'wss://$wsUrl';
    }
    return Uri.parse(wsUrl);
  }

  Map<String, String>? _buildHeaders() {
    if (!kIsWeb && apiKey != null && apiKey!.isNotEmpty) {
      return {'Authorization': 'Bearer $apiKey'};
    }
    return null;
  }

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    if (_status == AsrStatus.recognizing || _status == AsrStatus.connecting) {
      return;
    }
    _audioBuffer.clear();
    _taskStarted = false;
    _currentTaskId = null;
    try {
      _updateStatus(AsrStatus.connecting);
      _audioSub = audioStream.listen(
        (audioData) => _sendAudioData(audioData),
        onError: (error) => _updateStatus(AsrStatus.error),
      );
      final wsUri = _buildWsUri();
      final headers = _buildHeaders();
      if (!kIsWeb) {
        _channel = IOWebSocketChannel.connect(wsUri, headers: headers);
      } else {
        _channel = WebSocketChannel.connect(wsUri);
      }
      _wsSub = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) => _updateStatus(AsrStatus.error),
        onDone: () {
          if (_status == AsrStatus.recognizing) {
            _updateStatus(AsrStatus.disconnected);
          }
        },
      );
      await _channel!.ready.timeout(_connectionTimeout, onTimeout: () {
        throw TimeoutException(
            '百炼 WebSocket 连接超时 (${_connectionTimeout.inSeconds}秒)');
      });
      _sendRunTask();
    } catch (e) {
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  void _sendRunTask() {
    if (_channel == null) return;
    _currentTaskId = const Uuid().v4();
    final msg = jsonEncode({
      'header': {
        'action': 'run-task',
        'task_id': _currentTaskId,
        'streaming': 'duplex',
      },
      'payload': {
        'task_group': 'audio',
        'task': 'asr',
        'function': 'recognition',
        'model': modelName ?? 'fun-asr-realtime',
        'parameters': {
          'format': 'pcm',
          'sample_rate': 16000,
          'speaker_diarization_enabled': true,
          if (_extraParams['disfluency_removal_enabled'] != null)
            'disfluency_removal_enabled':
                _extraParams['disfluency_removal_enabled'],
        },
        'input': {},
      },
    });
    try {
      _channel!.sink.add(msg);
    } catch (_) {}
  }

  void _sendAudioData(Uint8List data) {
    if (_channel == null) return;
    audioBytesSent += data.length;
    audioChunksSent++;
    if (!_taskStarted || _isFlushing) {
      if (_audioBuffer.length < _maxBufferSize) {
        _audioBuffer.add(data);
      }
      return;
    }
    _channel!.sink.add(data);
  }

  void _flushAudioBuffer() {
    if (_channel == null || _audioBuffer.isEmpty) return;
    _isFlushing = true;
    for (final chunk in _audioBuffer) {
      _channel!.sink.add(chunk);
    }
    _audioBuffer.clear();
    _isFlushing = false;
  }

  void _handleServerMessage(dynamic message) {
    wsMessagesReceived++;
    String? messageStr;
    if (message is String) {
      messageStr = message;
    } else if (message is ByteBuffer) {
      messageStr = utf8.decode(message.asUint8List());
    } else if (message is List<int>) {
      messageStr = utf8.decode(message);
    }
    if (messageStr == null) return;
    debugPrint('[ASR] WS收到: ${messageStr.length > 200 ? messageStr.substring(0, 200) + '...' : messageStr}');
    try {
      final data = jsonDecode(messageStr) as Map<String, dynamic>;
      final header = data['header'] as Map<String, dynamic>?;
      if (header == null) return;
      final event = (header['action'] ?? header['event']) as String?;
      if (event == null) return;
      debugPrint('[ASR] 事件: $event');
      switch (event) {
        case 'task-started':
          _taskStarted = true;
          _updateStatus(AsrStatus.recognizing);
          _flushAudioBuffer();
          break;
        case 'result-generated':
          _handleResultGenerated(data);
          break;
        case 'task-finished':
          _updateStatus(AsrStatus.stopped);
          break;
        case 'task-failed':
        case 'failed':
        case 'error':
          debugPrint('[ASR] 错误事件: $messageStr');
          _updateStatus(AsrStatus.error);
          break;
      }
    } catch (e) {
      debugPrint('[ASR] 解析消息失败: $e');
    }
  }

  void _handleResultGenerated(Map<String, dynamic> data) {
    final payload = data['payload'] as Map<String, dynamic>?;
    final output = payload?['output'] as Map<String, dynamic>?;
    debugPrint('[ASR] result-generated output: $output');
    final sentence = output?['sentence'] as Map<String, dynamic>?;
    if (sentence == null) {
      // 尝试直接从 output 获取 text
      final text = output?['text'] as String?;
      if (text != null && text.isNotEmpty) {
        debugPrint('[ASR] 从 output.text 获取: $text');
        wsTextResultsReceived++;
        _transcriptionController.add(AsrResult(
          text: text,
          isFinal: output?['sentence_end'] == true,
          speaker: output?['speaker_id'] as String?,
        ));
      }
      return;
    }
    final text = sentence['text'] as String?;
    if (text == null || text.isEmpty) return;
    debugPrint('[ASR] 识别文本: $text (final: ${sentence['sentence_end']})');
    wsTextResultsReceived++;
    final isSentenceEnd = sentence['sentence_end'] == true;
    final speakerId = sentence['speaker_id'] as String?;
    _transcriptionController.add(AsrResult(
      text: text,
      isFinal: isSentenceEnd,
      speaker: speakerId,
    ));
  }

  Future<void> _sendFinishTask() async {
    if (_channel == null || _currentTaskId == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'header': {'action': 'finish-task', 'task_id': _currentTaskId},
        'payload': {'input': {}},
      }));
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    await _sendFinishTask();
    await Future.delayed(const Duration(milliseconds: 500));
    await _cleanup();
    _updateStatus(AsrStatus.stopped);
  }

  Future<void> _cleanup() async {
    _taskStarted = false;
    _currentTaskId = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _cleanup();
    disposeControllers();
  }
}

/// 本地 FunASR WebSocket 服务
class LocalFunASRService extends AsrService with AsrServiceMixin {
  final String url;
  final String? modelName;

  WebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  bool _isConnected = false;

  static const _connectionTimeout = Duration(seconds: 10);

  LocalFunASRService({required this.url, this.modelName});

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    if (_status == AsrStatus.recognizing || _status == AsrStatus.connecting) {
      return;
    }
    try {
      _updateStatus(AsrStatus.connecting);
      final wsUri = Uri.parse(url);
      _channel = WebSocketChannel.connect(wsUri);
      _audioSub = audioStream.listen(
        (audioData) => _sendAudioData(audioData),
        onError: (error) => _updateStatus(AsrStatus.error),
      );
      _wsSub = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) => _updateStatus(AsrStatus.error),
        onDone: () {
          if (_status == AsrStatus.recognizing) {
            _updateStatus(AsrStatus.disconnected);
          }
        },
      );
      await _channel!.ready.timeout(_connectionTimeout, onTimeout: () {
        throw TimeoutException('本地 ASR 连接超时 (${_connectionTimeout.inSeconds}秒)');
      });
      _isConnected = true;
      _updateStatus(AsrStatus.recognizing);
    } catch (e) {
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  void _sendAudioData(Uint8List data) {
    if (_channel == null || !_isConnected) return;
    try { _channel!.sink.add(data); } catch (_) {}
  }

  void _handleServerMessage(dynamic message) {
    String? messageStr;
    if (message is String) {
      messageStr = message;
    } else if (message is ByteBuffer) {
      messageStr = utf8.decode(message.asUint8List());
    } else if (message is List<int>) {
      messageStr = utf8.decode(message);
    }
    if (messageStr == null) return;
    try {
      final data = jsonDecode(messageStr) as Map<String, dynamic>;
      String? text;
      bool isFinal = false;
      if (data.containsKey('text')) {
        text = data['text'] as String?;
        isFinal = data['is_final'] as bool? ?? false;
      } else if (data.containsKey('result')) {
        final result = data['result'] as Map<String, dynamic>;
        text = result['text'] as String?;
        isFinal = result['is_final'] as bool? ?? false;
      }
      if (text != null && text.isNotEmpty) {
        _transcriptionController.add(AsrResult(text: text, isFinal: isFinal));
      }
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _isConnected = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _updateStatus(AsrStatus.stopped);
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _wsSub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    disposeControllers();
  }
}

/// 本地 sherpa-onnx 离线 ASR（SenseVoice + Silero VAD）
///
/// 音频管线：麦克风 PCM → VAD 检测语音段 → SenseVoice ASR → 文本结果
class SherpaOnnxAsrService extends AsrService with AsrServiceMixin {
  final String modelPath;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VoiceActivityDetector? _vad;
  sherpa_onnx.CircularBuffer? _circularBuffer;
  StreamSubscription? _audioSub;
  bool _isProcessing = false;

  static const _sampleRate = 16000;

  SherpaOnnxAsrService({required this.modelPath});

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    if (_status == AsrStatus.recognizing || _status == AsrStatus.connecting) {
      return;
    }

    try {
      _updateStatus(AsrStatus.connecting);

      // 验证模型目录存在
      if (!Directory(modelPath).existsSync()) {
        throw Exception('模型目录不存在: $modelPath');
      }

      // 初始化 sherpa-onnx native bindings
      try {
        sherpa_onnx.initBindings();
        debugPrint('[SherpaOnnxASR] Native bindings 已初始化');
      } catch (e) {
        throw Exception('sherpa-onnx native 库初始化失败: $e\n请确认 sherpa_onnx 插件已正确安装');
      }

      // 自动检测模型目录（可能在子目录中）
      final actualModelPath = _detectModelPath(modelPath);
      debugPrint('[SherpaOnnxASR] 基础目录: $modelPath');
      debugPrint('[SherpaOnnxASR] 实际模型目录: $actualModelPath');

      // 列出模型目录内容，便于调试
      try {
        final dirContents = Directory(actualModelPath).listSync();
        debugPrint('[SherpaOnnxASR] 模型目录内容:');
        for (final entity in dirContents) {
          final name = entity.path.split(Platform.pathSeparator).last;
          final size = entity is File ? '${(entity.lengthSync() / 1024).toStringAsFixed(0)} KB' : 'DIR';
          debugPrint('  - $name ($size)');
        }
      } catch (_) {}

      // 查找模型文件（支持多种文件名：sherpa-onnx 和 FunASR 格式）
      // 官方 int8 量化版优先（精度与速度最佳平衡）
      final modelFile = _findModelFile(actualModelPath, [
        'model.int8.onnx',  // 官方 int8 量化版（推荐，228MB）
        'model.onnx',       // 原版 float32（894MB）
        'model_quant.onnx', // FunASR ONNX 量化版
      ]);

      // 后处理：如果 tokens.txt 不存在但 tokens.json 存在，自动转换
      var tokensFile = File('$actualModelPath/tokens.txt');
      if (!tokensFile.existsSync()) {
        final tokensJsonFile = File('$actualModelPath/tokens.json');
        if (tokensJsonFile.existsSync()) {
          debugPrint('[SherpaOnnxASR] tokens.txt 不存在，从 tokens.json 转换...');
          try {
            final jsonContent = await tokensJsonFile.readAsString();
            final List<dynamic> tokens = jsonDecode(jsonContent);
            final buffer = StringBuffer();
            for (final token in tokens) {
              buffer.writeln(token.toString());
            }
            await tokensFile.writeAsString(buffer.toString());
            debugPrint('[SherpaOnnxASR] tokens.json → tokens.txt 转换完成（${tokens.length} 个 token）');
          } catch (e) {
            debugPrint('[SherpaOnnxASR] tokens.json 转换失败: $e');
          }
        }
      }
      // VAD 可能在实际模型目录、上级目录，或打包在 app assets 中
      var vadFile = File('$actualModelPath/silero_vad.onnx');
      if (!vadFile.existsSync()) {
        vadFile = File('${Directory(actualModelPath).parent.path}/silero_vad.onnx');
      }
      if (!vadFile.existsSync()) {
        // 从 assets 提取到临时目录
        try {
          final data = await rootBundle.load('assets/silero_vad.onnx');
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/silero_vad.onnx');
          await tempFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          vadFile = tempFile;
          debugPrint('[SherpaOnnxASR] VAD 模型已从 assets 提取到 ${tempFile.path}');
        } catch (e) {
          debugPrint('[SherpaOnnxASR] 从 assets 加载 VAD 失败: $e');
        }
      }

      if (modelFile == null) {
        throw Exception(
          'ASR 模型文件不存在\n'
          '搜索目录: $actualModelPath\n'
          '期望文件: model.int8.onnx / model.onnx / model_quant.onnx\n'
          '请确认模型已正确下载到该目录'
        );
      }
      if (!tokensFile.existsSync()) {
        throw Exception(
          'Tokens 文件不存在: ${tokensFile.path}\n'
          '请确认模型已完整下载'
        );
      }

      debugPrint('[SherpaOnnxASR] 模型文件: ${modelFile.path}');
      debugPrint('[SherpaOnnxASR] Tokens 文件: ${tokensFile.path}');
      debugPrint('[SherpaOnnxASR] VAD 文件: ${vadFile.existsSync() ? vadFile.path : "未找到"}');

      // 验证模型文件（防止加载不完整/损坏文件导致 native crash）
      final modelFileSize = modelFile.lengthSync();
      debugPrint('[SherpaOnnxASR] 模型文件大小: $modelFileSize 字节 (${(modelFileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // 从 kAvailableModels 查找期望的文件大小
      int expectedSize = 0;
      for (final m in kAvailableModels) {
        for (final f in m.files) {
          if (f.filename == modelFile.path.split(Platform.pathSeparator).last && f.sizeBytes > 0) {
            expectedSize = f.sizeBytes;
            break;
          }
        }
        if (expectedSize > 0) break;
      }

      if (expectedSize > 0 && modelFileSize != expectedSize) {
        throw Exception(
          '模型文件大小不匹配！\n'
          '期望: ${(expectedSize / 1024 / 1024).toStringAsFixed(1)} MB ($expectedSize 字节)\n'
          '实际: ${(modelFileSize / 1024 / 1024).toStringAsFixed(1)} MB ($modelFileSize 字节)\n'
          '请在模型管理中删除后重新下载。'
        );
      }
      if (modelFileSize < 1024 * 1024) {
        throw Exception(
          '模型文件过小（${(modelFileSize / 1024).toStringAsFixed(0)} KB），可能下载不完整。\n'
          '请在模型管理中删除后重新下载。'
        );
      }

      // 检测模型类型：SenseVoice 还是 Paraformer
      // SenseVoice tokens.txt 包含 `<|zh|>` 等语言标记
      bool isSenseVoice = false;
      try {
        final tokensContent = await tokensFile.readAsString();
        isSenseVoice = tokensContent.contains('<|zh|>');
      } catch (_) {}

      // 根据模型类型创建配置
      sherpa_onnx.OfflineModelConfig modelConfig;
      if (isSenseVoice) {
        debugPrint('[SherpaOnnxASR] 检测到 SenseVoice 模型');
        final senseVoiceConfig = sherpa_onnx.OfflineSenseVoiceModelConfig(
          model: modelFile.path,
          language: 'auto',
          useInverseTextNormalization: true,
        );
        modelConfig = sherpa_onnx.OfflineModelConfig(
          senseVoice: senseVoiceConfig,
          tokens: tokensFile.path,
          numThreads: 4,
          debug: false,
          modelType: 'sense_voice',
        );
      } else {
        debugPrint('[SherpaOnnxASR] 检测到 Paraformer 模型');
        final paraformerConfig = sherpa_onnx.OfflineParaformerModelConfig(
          model: modelFile.path,
        );
        modelConfig = sherpa_onnx.OfflineModelConfig(
          paraformer: paraformerConfig,
          tokens: tokensFile.path,
          numThreads: 4,
          debug: false,
          modelType: 'paraformer',
        );
      }
      // 加载热词文件（从 assets 提取）
      String hotwordsPath = '';
      try {
        final hotwordsData = await rootBundle.load('assets/hotwords.txt');
        final tempDir = await getTemporaryDirectory();
        final hotwordsFile = File('${tempDir.path}/hotwords.txt');
        await hotwordsFile.writeAsBytes(
          hotwordsData.buffer.asUint8List(hotwordsData.offsetInBytes, hotwordsData.lengthInBytes),
        );
        hotwordsPath = hotwordsFile.path;
        debugPrint('[SherpaOnnxASR] 热词文件已提取到 $hotwordsPath');
      } catch (e) {
        debugPrint('[SherpaOnnxASR] 热词文件加载失败: $e');
      }

      final recognizerConfig = sherpa_onnx.OfflineRecognizerConfig(
        model: modelConfig,
        hotwordsFile: hotwordsPath,
        hotwordsScore: 1.5,
      );
      debugPrint('[SherpaOnnxASR] 创建识别器...');
      debugPrint('[SherpaOnnxASR] 模型路径: ${modelFile.path} (exists: ${modelFile.existsSync()})');
      debugPrint('[SherpaOnnxASR] Tokens路径: ${tokensFile.path} (exists: ${tokensFile.existsSync()})');
      debugPrint('[SherpaOnnxASR] 热词路径: $hotwordsPath (exists: ${File(hotwordsPath).existsSync()})');
      try {
        _recognizer = sherpa_onnx.OfflineRecognizer(recognizerConfig);
        debugPrint('[SherpaOnnxASR] 识别器已初始化（热词: $hotwordsPath）');
      } catch (e) {
        debugPrint('[SherpaOnnxASR] 识别器创建失败: $e');
        // 尝试不带热词创建
        debugPrint('[SherpaOnnxASR] 尝试不带热词创建识别器...');
        final noHotwordsConfig = sherpa_onnx.OfflineRecognizerConfig(
          model: modelConfig,
        );
        _recognizer = sherpa_onnx.OfflineRecognizer(noHotwordsConfig);
        debugPrint('[SherpaOnnxASR] 识别器已初始化（无热词）');
      }

      // 初始化 Silero VAD（如果模型文件存在）
      if (vadFile.existsSync()) {
        final vadConfig = sherpa_onnx.VadModelConfig(
          sileroVad: sherpa_onnx.SileroVadModelConfig(
            model: vadFile.path,
            threshold: 0.3,           // 降低阈值，更容易检测到语音
            minSilenceDuration: 0.8,  // 增加静音时长，避免过早截断
            minSpeechDuration: 0.25,  // 允许更短的语音段
            maxSpeechDuration: 60.0,  // 增加最大语音段时长，适合会议场景
            windowSize: 512,
          ),
          sampleRate: _sampleRate,
          numThreads: 2,
          debug: false,
        );
        _vad = sherpa_onnx.VoiceActivityDetector(
          config: vadConfig,
          bufferSizeInSeconds: 60,
        );
        debugPrint('[SherpaOnnxASR] Silero VAD 已初始化');
      } else {
        debugPrint('[SherpaOnnxASR] 未找到 VAD 模型，跳过 VAD（将使用无 VAD 模式）');
      }

      // 初始化环形缓冲区（保留 120 秒音频，适应会议长语音段）
      _circularBuffer = sherpa_onnx.CircularBuffer(capacity: _sampleRate * 120);

      _updateStatus(AsrStatus.recognizing);

      // 订阅音频流
      _audioSub = audioStream.listen(
        _onAudioData,
        onError: (error) {
          debugPrint('[SherpaOnnxASR] 音频流错误: $error');
          _updateStatus(AsrStatus.error);
        },
        onDone: () {
          debugPrint('[SherpaOnnxASR] 音频流已结束');
          if (_status == AsrStatus.recognizing) {
            _processRemainingAudio();
          }
        },
      );

      debugPrint('[SherpaOnnxASR] 已启动，等待音频...');
    } catch (e) {
      debugPrint('[SherpaOnnxASR] 启动失败: $e');
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  int _totalAudioBytes = 0;
  int _onAudioCallCount = 0;

  // 累积 Float32 样本（无 VAD 模式直接送识别器）
  final List<Float32List> _pendingSamples = [];
  int _pendingSampleCount = 0;

  void _onAudioData(Uint8List data) {
    _onAudioCallCount++;
    _totalAudioBytes += data.length;
    if (_onAudioCallCount <= 5 || _onAudioCallCount % 50 == 0) {
      debugPrint('[SherpaOnnxASR] 收到音频 #$_onAudioCallCount: ${data.length} bytes, 累计 ${(_totalAudioBytes / 1024).toStringAsFixed(1)} KB');
    }

    if (_circularBuffer == null) {
      debugPrint('[SherpaOnnxASR] 错误: circularBuffer 为 null');
      return;
    }

    // 将 PCM 16-bit LE 字节转换为 Float32 归一化 [-1, 1]
    final floatSamples = _pcm16ToFloat32(data);
    _circularBuffer!.push(floatSamples);

    // 先尝试 VAD，如果 VAD 不触发则降级为累积模式
    if (_vad != null) {
      _processVad();
    }

    // 无论 VAD 是否触发，都累积音频用于 fallback
    _pendingSamples.add(floatSamples);
    _pendingSampleCount += floatSamples.length;

    // 累积约 5 秒音频后直接送识别器（兜底机制，提供更多上下文）
    if (_pendingSampleCount >= _sampleRate * 5 && !_isProcessing) {
      _processPendingSamples();
    }
  }

  void _processVad() {
    if (_vad == null || _circularBuffer == null) return;

    // 将新音频送入 VAD
    final bufferedSize = _circularBuffer!.size;
    if (bufferedSize > 0) {
      final samples = _circularBuffer!.get(
        startIndex: _circularBuffer!.head,
        n: bufferedSize,
      );
      _vad!.acceptWaveform(samples);
      _circularBuffer!.pop(bufferedSize);
      if (_onAudioCallCount <= 10 || _onAudioCallCount % 100 == 0) {
        debugPrint('[SherpaOnnxASR] VAD 输入 ${samples.length} 样本 (${(samples.length / _sampleRate).toStringAsFixed(2)}s), 检测中=${_vad!.isDetected()}, 队列=${!_vad!.isEmpty()}');
      }
    }

    // 处理检测到的语音段
    while (!_vad!.isEmpty()) {
      final segment = _vad!.front();
      _vad!.pop();
      debugPrint('[SherpaOnnxASR] VAD 检测到语音段: ${segment.samples.length} 样本 (${(segment.samples.length / _sampleRate).toStringAsFixed(2)}s)');

      if (segment.samples.isNotEmpty) {
        _processSpeechSegment(segment.samples);
      }
    }
  }

  /// 将累积的 Float32 样本合并后送识别器
  void _processPendingSamples() {
    if (_pendingSampleCount == 0 || _isProcessing) return;

    // 合并所有累积的样本
    final merged = Float32List(_pendingSampleCount);
    int offset = 0;
    for (final chunk in _pendingSamples) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _pendingSamples.clear();
    _pendingSampleCount = 0;

    debugPrint('[SherpaOnnxASR] 直接识别 ${merged.length} 样本 (${(merged.length / _sampleRate).toStringAsFixed(1)}s)');
    _processSpeechSegment(merged);
  }

  void _processSpeechSegment(Float32List samples) {
    if (_recognizer == null || samples.isEmpty) {
      debugPrint('[SherpaOnnxASR] 跳过识别: recognizer=${_recognizer != null}, samples=${samples.length}');
      return;
    }

    _isProcessing = true;
    debugPrint('[SherpaOnnxASR] 开始识别 ${samples.length} 样本 (${(samples.length / _sampleRate).toStringAsFixed(2)}s)...');

    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();

      debugPrint('[SherpaOnnxASR] 识别完成: "${result.text}" (长度=${result.text.length})');
      if (result.text.trim().isNotEmpty) {
        _transcriptionController.add(AsrResult(
          text: result.text.trim(),
          isFinal: true,
        ));
      }
    } catch (e) {
      debugPrint('[SherpaOnnxASR] 识别出错: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _processRemainingAudio() {
    debugPrint('[SherpaOnnxASR] 处理剩余音频...');

    // 处理 VAD 队列中的剩余语音段
    if (_vad != null) {
      _vad!.flush();
      while (!_vad!.isEmpty()) {
        final segment = _vad!.front();
        _vad!.pop();
        if (segment.samples.isNotEmpty) {
          _processSpeechSegment(segment.samples);
        }
      }
    }

    // 处理环形缓冲区中的剩余音频
    if (_circularBuffer != null && _circularBuffer!.size > 0) {
      final samples = _circularBuffer!.get(
        startIndex: 0,
        n: _circularBuffer!.size,
      );
      _circularBuffer!.reset();
      if (samples.isNotEmpty) {
        _processSpeechSegment(samples);
      }
    }

    // 处理累积的 Float32 样本
    _processPendingSamples();

    debugPrint('[SherpaOnnxASR] 剩余音频处理完毕');
  }

  /// PCM 16-bit → Float32 [-1, 1]
  /// 使用手动字节读取，避免 ByteData.view 的 buffer offset 问题
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final int sampleCount = bytes.length ~/ 2;
    final Float32List result = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final lo = bytes[i * 2];
      final hi = bytes[i * 2 + 1];
      // 尝试 little-endian（Android ARM 标准）
      final sampleLE = (lo | (hi << 8));
      final value = (sampleLE << 16) >> 16; // 符号扩展
      result[i] = value / 32768.0;
    }
    // 打印前 10 个样本的原始字节和转换值，用于诊断
    if (_onAudioCallCount <= 3 && sampleCount >= 10) {
      final rawBytes = bytes.take(20).toList();
      final samples = result.take(10).toList();
      debugPrint('[SherpaOnnxASR] PCM 诊断: bytes=$rawBytes');
      debugPrint('[SherpaOnnxASR] PCM 诊断: samples=${samples.map((s) => s.toStringAsFixed(4)).toList()}');
      // 检查是否有有效音频（非全零、非全静音）
      final maxAmplitude = result.fold(0.0, (max, s) => s.abs() > max ? s.abs() : max);
      debugPrint('[SherpaOnnxASR] PCM 诊断: 最大振幅=${maxAmplitude.toStringAsFixed(4)}');
    }
    return result;
  }

  @override
  Future<void> stop() async {
    // 停止前先处理所有剩余音频（VAD 队列 + 环形缓冲区）
    _processRemainingAudio();
    _updateStatus(AsrStatus.stopped);
    await _cleanup();
  }

  /// 自动检测模型目录（递归搜索，处理 tar.bz2 解压后的子目录结构）
  String _detectModelPath(String basePath) {
    final baseDir = Directory(basePath);
    if (!baseDir.existsSync()) return basePath;

    // 检查是否直接包含模型文件
    if (File('$basePath/tokens.txt').existsSync()) {
      return basePath;
    }

    // 递归搜索子目录（最多 3 层）
    return _searchSubdirs(baseDir, 0) ?? basePath;
  }

  String? _searchSubdirs(Directory dir, int depth) {
    if (depth > 3) return null;

    try {
      final subdirs = dir.listSync().whereType<Directory>().toList();
      for (final subdir in subdirs) {
        if (File('${subdir.path}/tokens.txt').existsSync()) {
          debugPrint('[SherpaOnnxASR] 找到模型子目录: ${subdir.path}');
          return subdir.path;
        }
        // 递归搜索更深层目录
        final deeper = _searchSubdirs(subdir, depth + 1);
        if (deeper != null) return deeper;
      }
    } catch (_) {}

    return null;
  }

  /// 查找模型文件（支持多种文件名）
  File? _findModelFile(String dirPath, List<String> candidates) {
    for (final filename in candidates) {
      final file = File('$dirPath/$filename');
      if (file.existsSync()) {
        debugPrint('[SherpaOnnxASR] 找到模型文件: ${file.path}');
        return file;
      }
    }
    debugPrint('[SherpaOnnxASR] 模型文件未找到，候选: $candidates');
    return null;
  }

  Future<void> _cleanup() async {
    await _audioSub?.cancel();
    _audioSub = null;

    _vad?.free();
    _vad = null;

    _circularBuffer?.free();
    _circularBuffer = null;

    _recognizer?.free();
    _recognizer = null;
  }

  @override
  void dispose() {
    _cleanup();
    disposeControllers();
  }
}

/// MiMo-V2.5-ASR 云端语音识别（HTTP API，OpenAI 兼容格式）
///
/// 音频管线：麦克风 PCM → 定时打包 WAV → Base64 → MiMo ASR API → 文本结果
class MiMoAsrService extends AsrService with AsrServiceMixin {
  final String apiKey;
  final String? language;
  final int sendIntervalSec;

  StreamSubscription? _audioSub;
  final List<int> _pcmBuffer = [];
  Timer? _sendTimer;
  bool _isProcessing = false;

  static const _sampleRate = 16000;
  static const _channels = 1;
  static const _bitsPerSample = 16;
  static const _apiUrl = 'https://api.xiaomimimo.com/v1/chat/completions';

  MiMoAsrService({
    required this.apiKey,
    this.language,
    this.sendIntervalSec = 3,
  });

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    if (_status == AsrStatus.recognizing || _status == AsrStatus.connecting) {
      return;
    }
    _pcmBuffer.clear();
    _isProcessing = false;
    try {
      _updateStatus(AsrStatus.connecting);
      _audioSub = audioStream.listen(
        (audioData) => _pcmBuffer.addAll(audioData),
        onError: (error) => _updateStatus(AsrStatus.error),
      );
      _sendTimer = Timer.periodic(
        Duration(seconds: sendIntervalSec),
        (_) => _sendAudio(),
      );
      _updateStatus(AsrStatus.recognizing);
      // 首次立即发送（如果有数据）
      Future.delayed(const Duration(milliseconds: 500), () => _sendAudio());
    } catch (e) {
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  Future<void> _sendAudio() async {
    if (_pcmBuffer.isEmpty || _isProcessing) return;
    _isProcessing = true;

    // 取出缓冲区数据
    final pcmData = Uint8List.fromList(_pcmBuffer);
    _pcmBuffer.clear();

    try {
      // PCM → WAV
      final wavData = _pcmToWav(pcmData);
      final base64Audio = base64Encode(wavData);
      final dataUrl = 'data:audio/wav;base64,$base64Audio';

      final body = jsonEncode({
        'model': 'mimo-v2.5-asr',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_audio',
                'input_audio': {'data': dataUrl},
              },
            ],
          },
        ],
        'asr_options': {
          'language': language ?? 'auto',
        },
        'stream': false,
      });

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            _transcriptionController.add(AsrResult(text: content, isFinal: true));
          }
        }
      } else {
        debugPrint('[MiMoASR] 请求失败: HTTP ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[MiMoASR] 发送音频失败: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// PCM 16-bit LE → WAV
  Uint8List _pcmToWav(Uint8List pcm) {
    final int byteRate = _sampleRate * _channels * _bitsPerSample ~/ 8;
    final int blockAlign = _channels * _bitsPerSample ~/ 8;
    final int dataSize = pcm.length;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // sub-chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, _channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);
    // data sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + dataSize);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(44, pcm);
    return result;
  }

  @override
  Future<void> stop() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    // 发送剩余音频
    await _sendAudio();
    await _audioSub?.cancel();
    _audioSub = null;
    _pcmBuffer.clear();
    _updateStatus(AsrStatus.stopped);
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _audioSub?.cancel();
    disposeControllers();
  }
}

/// ASR 服务工厂
class AsrServiceFactory {
  static AsrService create(ASRModelConfig config) {
    switch (config.type) {
      case 'websocket':
        return FunASRRealtimeService(
          url: config.url,
          apiKey: config.key,
          modelName: config.modelName,
          extraParams: {
            if (config.modelName != null) 'model': config.modelName,
          },
        );
      case 'local_funasr':
        return LocalFunASRService(
          url: config.url,
          modelName: config.modelName,
        );
      case 'local_funasr_onnx':
        return SherpaOnnxAsrService(
          modelPath: config.modelPath ?? '',
        );
      case 'http':
        return MiMoAsrService(
          apiKey: config.key,
          language: config.modelName,
          sendIntervalSec: config.httpAsrIntervalSec,
        );
      default:
        return NoOpAsrService();
    }
  }
}
