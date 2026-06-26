import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 音频录制器状态
enum RecorderState { idle, recording, paused, error }

/// 统一音频录制服务
/// 录音期间仅使用 PCM recorder（给 ASR 流式传输 + 累积数据）
/// 录音结束后返回累积的 PCM 数据（用于 WAV 保存）
/// 避免了双 recorder 并发导致 PCM 流被杀死的问题
class AudioRecorderService {
  // PCM 流式 recorder（给 ASR）
  AudioRecorder? _pcmRecorder;
  RecorderState _state = RecorderState.idle;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _captureSub;
  int _recordingDuration = 0;
  Timer? _durationTimer;
  String? _lastError;

  // Opus 输出路径（录音结束后写入文件）
  String? _opusOutputPath;

  // 累积 PCM 数据（用于 WAV 保存或后续 Opus 编码）
  final List<int> _accumulatedPcm = [];

  // 音频流健康监控
  Timer? _healthCheckTimer;
  int _lastAudioBytes = 0;
  bool _audioStreamAlive = false;

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  RecorderState get state => _state;
  int get recordingDuration => _recordingDuration;
  String? get lastError => _lastError;
  bool get isRecording => _state == RecorderState.recording;
  bool get isPaused => _state == RecorderState.paused;
  String? get opusOutputPath => _opusOutputPath;
  bool get isAudioStreamAlive => _audioStreamAlive;

  /// 开始录音
  /// 录音期间仅启动 PCM recorder（给 ASR 流式传输 + 累积数据）
  /// [opusOutputPath] 仅保存路径，暂未使用
  Future<void> startRecording({String? opusOutputPath}) async {
    if (_state == RecorderState.recording) return;

    try {
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          throw Exception('麦克风权限未授予');
        }
      }

      // === PCM recorder（给 ASR 流式传输 + 累积数据）===
      final pcmRecorder = AudioRecorder();
      if (!kIsWeb) {
        final hasPerm = await pcmRecorder.hasPermission(request: false);
        if (!hasPerm) {
          await pcmRecorder.dispose();
          throw Exception('麦克风权限未授予');
        }
      }

      final stream = await pcmRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _pcmRecorder = pcmRecorder;
      _state = RecorderState.recording;
      _recordingDuration = 0;
      _lastError = null;
      _accumulatedPcm.clear();

      // 保存 Opus 输出路径（录音结束后再写入文件）
      _opusOutputPath = opusOutputPath;

      int audioChunkCount = 0;
      int totalBytes = 0;
      _captureSub = stream.listen(
        (data) {
          audioChunkCount++;
          totalBytes += data.length;
          if (audioChunkCount <= 5 || audioChunkCount % 100 == 0) {
            debugPrint('[AudioRecorder] PCM 数据 #$audioChunkCount: ${data.length} bytes, 累计 ${(totalBytes / 1024).toStringAsFixed(1)} KB');
          }
          if (!_audioStreamController.isClosed) {
            _audioStreamController.add(data);
          }
          _audioStreamAlive = true;
          // 始终累积 PCM 数据（用于 WAV fallback 或后续 Opus 写入）
          _accumulatedPcm.addAll(data);
        },
        onError: (e) {
          _lastError = '音频采集错误: $e';
          debugPrint('[AudioRecorder] 流错误: $e');
        },
        onDone: () {
          debugPrint('[AudioRecorder] PCM 音频流已结束, 共 $audioChunkCount 块, ${(totalBytes / 1024).toStringAsFixed(1)} KB');
          _audioStreamAlive = false;
          if (_state == RecorderState.recording) {
            _lastError = '音频流意外中断';
            _state = RecorderState.error;
          }
        },
      );

      // 音频流健康监控：每 2 秒检查音频是否还在流动
      _audioStreamAlive = true;
      _lastAudioBytes = 0;
      _healthCheckTimer?.cancel();
      _healthCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_state != RecorderState.recording) {
          _healthCheckTimer?.cancel();
          return;
        }
        final currentBytes = _accumulatedPcm.length;
        if (currentBytes == _lastAudioBytes && currentBytes > 0) {
          debugPrint('[AudioRecorder] 警告: 音频流可能已停止 (已采集 ${currentBytes} bytes)');
        }
        _lastAudioBytes = currentBytes;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecorderState.recording) {
          _recordingDuration++;
        }
      });

      debugPrint('[AudioRecorder] 录音已启动（PCM 模式，Opus 将在停止后写入）');
    } catch (e) {
      _state = RecorderState.error;
      _lastError = e.toString();
      rethrow;
    }
  }

  /// 暂停录音
  Future<void> pauseRecording() async {
    if (_state != RecorderState.recording) return;

    try {
      await _pcmRecorder?.pause();
      _state = RecorderState.paused;
      _durationTimer?.cancel();
    } catch (e) {
      _lastError = '暂停录音失败: $e';
    }
  }

  /// 恢复录音
  Future<void> resumeRecording() async {
    if (_state != RecorderState.paused) return;

    try {
      await _pcmRecorder?.resume();
      _state = RecorderState.recording;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecorderState.recording) {
          _recordingDuration++;
        }
      });
    } catch (e) {
      _lastError = '恢复录音失败: $e';
    }
  }

  /// 停止录音
  /// 停止 PCM recorder，返回累积的 PCM 数据（用于 WAV 保存）
  Future<Uint8List?> stopRecording() async {
    _captureSub?.cancel();
    _captureSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    Uint8List? fallbackPcm;

    // 停止 PCM recorder
    try {
      await _pcmRecorder?.stop();
    } catch (_) {}
    try {
      await _pcmRecorder?.dispose();
    } catch (_) {}
    _pcmRecorder = null;

    // 返回累积的 PCM 数据（用于 WAV 保存）
    if (_accumulatedPcm.isNotEmpty) {
      fallbackPcm = Uint8List.fromList(_accumulatedPcm);
      debugPrint('[AudioRecorder] 停止录音，返回 ${(fallbackPcm.length / 1024).toStringAsFixed(1)} KB PCM 数据');
    } else {
      debugPrint('[AudioRecorder] 停止录音，无累积数据');
    }
    _accumulatedPcm.clear();
    _opusOutputPath = null;

    _state = RecorderState.idle;
    return fallbackPcm;
  }

  /// 释放资源
  void dispose() {
    _captureSub?.cancel();
    _captureSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    try { _pcmRecorder?.stop(); } catch (_) {}
    try { _pcmRecorder?.dispose(); } catch (_) {}
    _pcmRecorder = null;
    _audioStreamController.close();
  }
}

/// 将 PCM 数据保存为 WAV 文件
/// [pcmData] 16kHz 16bit 单声道 PCM 数据
/// [outputPath] 输出 WAV 文件路径
Future<void> savePcmAsWav(Uint8List pcmData, String outputPath) async {
  final file = File(outputPath);
  final sink = file.openWrite();

  final sampleRate = 16000;
  final bitsPerSample = 16;
  final numChannels = 1;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcmData.length;
  final fileSize = 36 + dataSize;

  final header = Uint8List(44);
  header[0] = 0x52; header[1] = 0x49; header[2] = 0x46; header[3] = 0x46;
  _writeInt32(header, 4, fileSize);
  header[8] = 0x57; header[9] = 0x41; header[10] = 0x56; header[11] = 0x45;
  _writeInt32(header, 16, 16);
  _writeInt16(header, 20, 1);
  _writeInt16(header, 22, numChannels);
  _writeInt32(header, 24, sampleRate);
  _writeInt32(header, 28, byteRate);
  _writeInt16(header, 32, blockAlign);
  _writeInt16(header, 34, bitsPerSample);
  header[36] = 0x64; header[37] = 0x61; header[38] = 0x74; header[39] = 0x61;
  _writeInt32(header, 40, dataSize);

  sink.add(header);
  sink.add(pcmData);
  await sink.flush();
  await sink.close();
}

void _writeInt16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
}

void _writeInt32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}
