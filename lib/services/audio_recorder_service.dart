import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 音频录制器状态
enum RecorderState { idle, recording, paused, error }

/// 统一音频录制服务
/// 方案 2：双 recorder 实例并发
/// - PCM recorder: startStream() → 流式 PCM 给 ASR
/// - Opus recorder: start(path) → 写 OGG Opus 文件
/// 如果 Opus recorder 启动失败（平台不支持双实例），fallback 到 WAV
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

  // Opus 文件 recorder
  AudioRecorder? _opusRecorder;
  bool _opusRecorderActive = false;
  String? _opusOutputPath;

  // Fallback: WAV 模式下累积 PCM 数据
  final List<int> _accumulatedPcm = [];

  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  RecorderState get state => _state;
  int get recordingDuration => _recordingDuration;
  String? get lastError => _lastError;
  bool get isRecording => _state == RecorderState.recording;
  bool get isPaused => _state == RecorderState.paused;
  bool get isOpusRecording => _opusRecorderActive;
  String? get opusOutputPath => _opusOutputPath;

  /// 开始录音
  /// [opusOutputPath] 如果提供，尝试同时写入 Opus 文件；失败则 fallback WAV
  Future<void> startRecording({String? opusOutputPath}) async {
    if (_state == RecorderState.recording) return;

    try {
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          throw Exception('麦克风权限未授予');
        }
      }

      // === PCM recorder（给 ASR）===
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

      _captureSub = stream.listen(
        (data) {
          if (!_audioStreamController.isClosed) {
            _audioStreamController.add(data);
          }
          // WAV fallback: 累积 PCM 数据
          if (!_opusRecorderActive) {
            _accumulatedPcm.addAll(data);
          }
        },
        onError: (e) {
          _lastError = '音频采集错误: $e';
        },
      );

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecorderState.recording) {
          _recordingDuration++;
        }
      });

      // === Opus recorder（并发尝试）===
      if (opusOutputPath != null) {
        _opusOutputPath = opusOutputPath;
        await _tryStartOpusRecorder(opusOutputPath);
      }
    } catch (e) {
      _state = RecorderState.error;
      _lastError = e.toString();
      rethrow;
    }
  }

  /// 尝试启动 Opus 文件 recorder
  /// 失败时静默降级到 WAV 模式
  Future<void> _tryStartOpusRecorder(String outputPath) async {
    try {
      final opusRecorder = AudioRecorder();
      if (!kIsWeb) {
        final hasPerm = await opusRecorder.hasPermission(request: false);
        if (!hasPerm) {
          await opusRecorder.dispose();
          return; // 静默降级
        }
      }

      await opusRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 32000, // 32kbps Opus，1小时 ≈ 14MB
        ),
        path: outputPath,
      );

      _opusRecorder = opusRecorder;
      _opusRecorderActive = true;
      print('Opus recorder 启动成功: $outputPath');
    } catch (e) {
      print('Opus recorder 启动失败，降级到 WAV: $e');
      _opusRecorderActive = false;
    }
  }

  /// 暂停录音（同时暂停两个 recorder）
  Future<void> pauseRecording() async {
    if (_state != RecorderState.recording) return;

    try {
      await _pcmRecorder?.pause();
      if (_opusRecorderActive) {
        await _opusRecorder?.pause();
      }
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
      if (_opusRecorderActive) {
        await _opusRecorder?.resume();
      }
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
  /// 返回值：如果 Opus recorder 失败（WAV fallback），返回累积的 PCM 数据
  Future<Uint8List?> stopRecording() async {
    _captureSub?.cancel();
    _captureSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    Uint8List? fallbackPcm;

    // 停止 PCM recorder
    try {
      await _pcmRecorder?.stop();
    } catch (_) {}
    try {
      await _pcmRecorder?.dispose();
    } catch (_) {}
    _pcmRecorder = null;

    // 停止 Opus recorder
    if (_opusRecorderActive) {
      try {
        await _opusRecorder?.stop();
      } catch (_) {}
      try {
        await _opusRecorder?.dispose();
      } catch (_) {}
      _opusRecorder = null;
      _opusRecorderActive = false;
      _opusOutputPath = null;
    } else {
      // WAV fallback: 返回累积的 PCM 数据
      if (_accumulatedPcm.isNotEmpty) {
        fallbackPcm = Uint8List.fromList(_accumulatedPcm);
      }
      _accumulatedPcm.clear();
    }

    _state = RecorderState.idle;
    return fallbackPcm;
  }

  /// 释放资源
  void dispose() {
    stopRecording();
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
