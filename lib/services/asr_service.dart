import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:yanji/utils/config_loader.dart';

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

/// 空实现（无 ASR 配置时使用）
class NoOpAsrService extends AsrService {
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

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    _status = AsrStatus.recognizing;
    _statusController.add(_status);
  }

  @override
  Future<void> stop() async {
    _status = AsrStatus.stopped;
    _statusController.add(_status);
  }

  @override
  void dispose() {
    _transcriptionController.close();
    _statusController.close();
  }
}

/// DashScope 百炼实时语音识别 WebSocket 实现
///
/// 协议说明：
/// 1. 建立 WebSocket 连接到百炼 api-ws/v1/inference 端点
/// 2. 发送 run-task JSON（指定模型、音频参数）
/// 3. 接收 task-started 确认
/// 4. 持续发送 PCM binary 帧（16kHz 16bit 单声道）
/// 5. 接收 result-generated JSON（实时识别结果）
/// 6. 发送 finish-task 结束任务
/// 7. 接收 task-finished 确认
class FunASRRealtimeService extends AsrService {
  final String url; // wss://dashscope.aliyuncs.com/api-ws/v1/inference
  final String? apiKey; // DashScope API Key
  final String? modelName; // 模型名: fun-asr-realtime / qwen3-asr-flash-realtime
  final Map<String, dynamic> _extraParams;

  WebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  String? _currentTaskId;
  bool _taskStarted = false;

  final StreamController<AsrResult> _transcriptionController =
      StreamController<AsrResult>.broadcast();
  final StreamController<AsrStatus> _statusController =
      StreamController<AsrStatus>.broadcast();
  AsrStatus _status = AsrStatus.disconnected;

  // 连接超时
  static const _connectionTimeout = Duration(seconds: 10);

  // 音频缓冲区：task-started 前缓存音频数据
  final List<Uint8List> _audioBuffer = [];
  static const int _maxBufferSize = 200;
  bool _isFlushing = false;

  // 调试计数器
  int audioBytesSent = 0;
  int audioChunksSent = 0;
  int wsMessagesReceived = 0;
  int wsTextResultsReceived = 0;

  @override
  Stream<AsrResult> get transcriptionStream => _transcriptionController.stream;

  @override
  Stream<AsrStatus> get statusStream => _statusController.stream;

  @override
  AsrStatus get status => _status;

  FunASRRealtimeService({
    required this.url,
    this.apiKey,
    this.modelName,
    Map<String, dynamic>? extraParams,
  }) : _extraParams = extraParams ?? {};

  /// 构造 WebSocket URI
  Uri _buildWsUri() {
    // 原生平台直连 DashScope（支持自定义 header），Web 走代理
    if (!kIsWeb && apiKey != null && apiKey!.isNotEmpty) {
      return Uri.parse('wss://dashscope.aliyuncs.com/api-ws/v1/inference');
    }
    // 自动修正协议：https→wss, http→ws
    var wsUrl = url.trim();
    if (wsUrl.startsWith('https://')) {
      wsUrl = 'wss://${wsUrl.substring(8)}';
    } else if (wsUrl.startsWith('http://')) {
      wsUrl = 'ws://${wsUrl.substring(7)}';
    }
    // 确保以 ws:// 或 wss:// 开头
    if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
      wsUrl = 'wss://$wsUrl';
    }
    debugPrint('[ASR] 原始 URL: "$url" → 修正后: "$wsUrl"');
    return Uri.parse(wsUrl);
  }

  /// 获取 WebSocket 连接所需的 HTTP header（仅原生平台有效）
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

      // 先订阅音频流（缓存数据，等 task-started 后发送）
      _audioSub = audioStream.listen(
        (audioData) => _sendAudioData(audioData),
        onError: (error) {
          _updateStatus(AsrStatus.error);
        },
      );

      final wsUri = _buildWsUri();
      final headers = _buildHeaders();
      debugPrint('[ASR] url="$url" apiKey="${apiKey ?? 'null'}" wsUri=$wsUri headers=${headers != null ? 'Bearer ***' : 'none'}');

      if (!kIsWeb) {
        _channel = IOWebSocketChannel.connect(wsUri, headers: headers);
      } else {
        _channel = WebSocketChannel.connect(wsUri);
      }

      // 接收服务端消息
      _wsSub = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) {
          debugPrint('[ASR] WebSocket 流错误: $error');
          _updateStatus(AsrStatus.error);
        },
        onDone: () {
          debugPrint('[ASR] WebSocket 连接关闭');
          if (_status == AsrStatus.recognizing) {
            _updateStatus(AsrStatus.disconnected);
          }
        },
      );

      // 等待 WebSocket 连接就绪
      debugPrint('[ASR] 等待 WebSocket 就绪...');
      await _channel!.ready.timeout(_connectionTimeout, onTimeout: () {
        debugPrint('[ASR] WebSocket 连接超时！');
        throw TimeoutException(
            '百炼 WebSocket 连接超时 (${_connectionTimeout.inSeconds}秒)');
      });
      debugPrint('[ASR] WebSocket 已就绪');

      // 发送 run-task 启动识别任务
      debugPrint('[ASR] 准备发送 run-task, channel=${_channel != null}, taskStarted=$_taskStarted');
      _sendRunTask();
    } catch (e) {
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  /// 发送 run-task 指令（百炼 WebSocket 协议）
  void _sendRunTask() {
    if (_channel == null) {
      debugPrint('[ASR] _sendRunTask: _channel 为 null，跳过');
      return;
    }

    _currentTaskId = const Uuid().v4();
    debugPrint('[ASR] _sendRunTask: task_id=$_currentTaskId');
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

    debugPrint('[ASR] _sendRunTask: 发送消息 (${msg.length} chars): ${msg.substring(0, 200)}...');
    try {
      _channel!.sink.add(msg);
      debugPrint('[ASR] _sendRunTask: 消息已发送');
    } catch (e) {
      debugPrint('[ASR] _sendRunTask: 发送失败: $e');
    }
  }

  /// 发送音频数据（binary frame）
  /// task-started 前缓存，就绪后发送
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

  /// 清空音频缓冲区
  void _flushAudioBuffer() {
    if (_channel == null || _audioBuffer.isEmpty) return;

    _isFlushing = true;
    for (final chunk in _audioBuffer) {
      _channel!.sink.add(chunk);
    }
    _audioBuffer.clear();
    _isFlushing = false;
  }

  /// 处理服务端消息
  void _handleServerMessage(dynamic message) {
    wsMessagesReceived++;
    debugPrint('[ASR] 收到消息 (type=${message.runtimeType}): $message');

    // 统一转为字符串处理（web 上二进制帧可能包含 JSON 文本）
    String? messageStr;
    if (message is String) {
      messageStr = message;
    } else if (message is ByteBuffer) {
      // web: web_socket_channel 可能将文本帧作为 ByteBuffer 传递
      messageStr = utf8.decode(message.asUint8List());
      debugPrint('[ASR] ByteBuffer 解码为文本: $messageStr');
    } else if (message is List<int>) {
      // native fallback
      messageStr = utf8.decode(message);
      debugPrint('[ASR] List<int> 解码为文本: $messageStr');
    }

    if (messageStr == null) {
      debugPrint('[ASR] 无法处理的消息类型: ${message.runtimeType}');
      return;
    }

    try {
      final data = jsonDecode(messageStr) as Map<String, dynamic>;
      final header = data['header'] as Map<String, dynamic>?;
      if (header == null) {
        debugPrint('[ASR] 无 header 的消息: $data');
        return;
      }

      // 百炼响应使用 event 字段（task-started 等），请求使用 action 字段（run-task 等）
      final event = (header['action'] ?? header['event']) as String?;
      if (event == null) return;

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

        case 'failed':
        case 'error':
          _updateStatus(AsrStatus.error);
          break;
      }
    } catch (e) {
      debugPrint('[ASR] 消息解析失败: $e, 原始消息: $messageStr');
    }
  }

  /// 解析 result-generated 事件中的识别结果
  void _handleResultGenerated(Map<String, dynamic> data) {
    final payload = data['payload'] as Map<String, dynamic>?;
    final output = payload?['output'] as Map<String, dynamic>?;
    final sentence = output?['sentence'] as Map<String, dynamic>?;
    if (sentence == null) return;

    final text = sentence['text'] as String?;
    if (text == null || text.isEmpty) return;

    wsTextResultsReceived++;
    final isSentenceEnd = sentence['sentence_end'] == true;

    // 提取说话人信息（DashScope 说话人分离返回的字段）
    final speakerId = sentence['speaker_id'] as String?;

    _transcriptionController.add(AsrResult(
      text: text,
      isFinal: isSentenceEnd,
      speaker: speakerId,
    ));
  }

  /// 发送 finish-task 结束识别
  Future<void> _sendFinishTask() async {
    if (_channel == null || _currentTaskId == null) return;

    try {
      final msg = jsonEncode({
        'header': {
          'action': 'finish-task',
          'task_id': _currentTaskId,
        },
        'payload': {},
      });
      _channel!.sink.add(msg);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    // 发送 finish-task 通知服务端结束
    await _sendFinishTask();

    // 等待服务端返回 task-finished 或最终结果
    await Future.delayed(const Duration(milliseconds: 500));

    await _cleanup();
    _updateStatus(AsrStatus.stopped);
  }

  void _updateStatus(AsrStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  Future<void> _cleanup() async {
    _taskStarted = false;
    _currentTaskId = null;

    await _audioSub?.cancel();
    _audioSub = null;

    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _cleanup();
    _transcriptionController.close();
    _statusController.close();
  }
}

/// 本地 FunASR WebSocket 服务（paraformer-zh-streaming 等本地部署模型）
class LocalFunASRService extends AsrService {
  final String url; // ws://localhost:10095
  final String? modelName; // paraformer-zh-streaming

  WebSocketChannel? _channel;
  StreamSubscription? _audioSub;
  StreamSubscription? _wsSub;
  bool _isConnected = false;

  final StreamController<AsrResult> _transcriptionController =
      StreamController<AsrResult>.broadcast();
  final StreamController<AsrStatus> _statusController =
      StreamController<AsrStatus>.broadcast();
  AsrStatus _status = AsrStatus.disconnected;

  static const _connectionTimeout = Duration(seconds: 10);

  // 调试计数器
  int audioBytesSent = 0;
  int audioChunksSent = 0;
  int wsMessagesReceived = 0;
  int wsTextResultsReceived = 0;

  @override
  Stream<AsrResult> get transcriptionStream => _transcriptionController.stream;

  @override
  Stream<AsrStatus> get statusStream => _statusController.stream;

  @override
  AsrStatus get status => _status;

  LocalFunASRService({
    required this.url,
    this.modelName,
  });

  @override
  Future<void> start({required Stream<Uint8List> audioStream}) async {
    if (_status == AsrStatus.recognizing || _status == AsrStatus.connecting) {
      return;
    }

    try {
      _updateStatus(AsrStatus.connecting);

      // 连接本地 FunASR WebSocket 服务
      final wsUri = Uri.parse(url);
      debugPrint('[LocalASR] 连接 WebSocket: $wsUri');

      _channel = WebSocketChannel.connect(wsUri);

      // 订阅音频流
      _audioSub = audioStream.listen(
        (audioData) => _sendAudioData(audioData),
        onError: (error) {
          debugPrint('[LocalASR] 音频流错误: $error');
          _updateStatus(AsrStatus.error);
        },
      );

      // 接收服务端消息
      _wsSub = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) {
          debugPrint('[LocalASR] WebSocket 错误: $error');
          _updateStatus(AsrStatus.error);
        },
        onDone: () {
          debugPrint('[LocalASR] WebSocket 连接关闭');
          if (_status == AsrStatus.recognizing) {
            _updateStatus(AsrStatus.disconnected);
          }
        },
      );

      // 等待连接就绪
      await _channel!.ready.timeout(_connectionTimeout, onTimeout: () {
        throw TimeoutException('本地 ASR 连接超时 (${_connectionTimeout.inSeconds}秒)');
      });

      _isConnected = true;
      _updateStatus(AsrStatus.recognizing);
      debugPrint('[LocalASR] 已连接，开始识别');

    } catch (e) {
      _updateStatus(AsrStatus.error);
      rethrow;
    }
  }

  /// 发送音频数据到本地 FunASR 服务
  void _sendAudioData(Uint8List data) {
    if (_channel == null || !_isConnected) return;

    audioBytesSent += data.length;
    audioChunksSent++;

    try {
      _channel!.sink.add(data);
    } catch (e) {
      debugPrint('[LocalASR] 发送音频失败: $e');
    }
  }

  /// 处理服务端消息（本地 FunASR 协议）
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

    try {
      final data = jsonDecode(messageStr) as Map<String, dynamic>;

      // 本地 FunASR 返回格式：{"text": "识别文本", "is_final": true/false}
      // 或者嵌套格式：{"result": {"text": "...", "is_final": ...}}
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
        wsTextResultsReceived++;
        _transcriptionController.add(AsrResult(
          text: text,
          isFinal: isFinal,
        ));
      }
    } catch (e) {
      debugPrint('[LocalASR] 消息解析失败: $e');
    }
  }

  @override
  Future<void> stop() async {
    _isConnected = false;

    await _audioSub?.cancel();
    _audioSub = null;

    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _updateStatus(AsrStatus.stopped);
  }

  void _updateStatus(AsrStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _wsSub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _transcriptionController.close();
    _statusController.close();
  }
}

/// ASR 服务工厂
class AsrServiceFactory {
  /// 根据配置创建对应的 ASR 服务实例
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
        // 本地部署的 FunASR 服务（paraformer-zh-streaming 等）
        return LocalFunASRService(
          url: config.url,
          modelName: config.modelName,
        );
      case 'http':
        // HTTP-based ASR（如 qwen-audio-turbo）在 LLMService 中处理
        // 这里返回 NoOpAsrService，转录在 recording screen 中通过 LLMService 完成
        return NoOpAsrService();
      default:
        return NoOpAsrService();
    }
  }
}
