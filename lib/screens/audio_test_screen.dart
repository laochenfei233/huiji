import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:yanji/services/audio_recorder_service.dart';
import 'package:yanji/services/cloud_storage_service.dart';
import 'package:yanji/services/config_service.dart';
import 'package:yanji/utils/config_loader.dart';

class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key});

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  final AudioRecorderService _audioRecorder = AudioRecorderService();

  // 麦克风测试状态
  bool _isRecording = false;
  int _audioDataCount = 0;
  int _totalBytes = 0;
  StreamSubscription? _audioStreamSubscription;

  // 网络测试状态
  bool _isTestingNetwork = false;
  String _networkTestResult = '';
  bool? _networkTestPassed;

  // ASR WebSocket 测试状态
  bool _isTestingAsr = false;
  String _asrTestResult = '';
  bool? _asrTestPassed;

  // LLM API 测试状态
  bool _isTestingLLM = false;
  String _llmTestResult = '';
  bool? _llmTestPassed;

  // S3 测试状态
  bool _isTestingS3 = false;
  String _s3TestResult = '';
  bool? _s3TestPassed;

  // WebDAV 测试状态
  bool _isTestingWebDAV = false;
  String _webdavTestResult = '';
  bool? _webdavTestPassed;

  final CloudStorageService _storageService = CloudStorageService();
  S3Config _s3Config = S3Config();
  WebDAVConfig _webdavConfig = WebDAVConfig();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _loadStorageConfig();
  }

  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    super.dispose();
  }

  // ==================== 麦克风测试 ====================

  void _toggleRecording() async {
    if (_isRecording) {
      await _audioRecorder.stopRecording();
      _audioStreamSubscription?.cancel();
      setState(() {
        _isRecording = false;
      });
    } else {
      setState(() {
        _isRecording = true;
        _audioDataCount = 0;
        _totalBytes = 0;
      });

      try {
        await _audioRecorder.startRecording();
        _audioStreamSubscription = _audioRecorder.audioStream.listen(
          (audioData) {
            setState(() {
              _audioDataCount++;
              _totalBytes += audioData.length;
            });
          },
          onError: (error) {
            setState(() {
              _isRecording = false;
            });
            _showSnackBar('音频流错误: $error');
          },
        );
      } catch (e) {
        setState(() {
          _isRecording = false;
        });
        _showSnackBar('录音启动失败: $e');
      }
    }
  }

  // ==================== 网络连接测试 ====================

  Future<void> _testNetwork() async {
    setState(() {
      _isTestingNetwork = true;
      _networkTestResult = '正在测试网络连接...';
      _networkTestPassed = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://dashscope.aliyuncs.com/compatible-mode/v1/models'),
        headers: {
          'Authorization': 'Bearer ${_getApiKey()}',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 401) {
        // 401 也说明网络可达，只是 key 问题
        setState(() {
          _networkTestPassed = true;
          _networkTestResult = '网络连接正常\n状态码: ${response.statusCode}';
        });
      } else {
        setState(() {
          _networkTestPassed = false;
          _networkTestResult = '请求失败\n状态码: ${response.statusCode}';
        });
      }
    } on TimeoutException {
      setState(() {
        _networkTestPassed = false;
        _networkTestResult = '连接超时 (10秒)\n请检查网络设置';
      });
    } catch (e) {
      setState(() {
        _networkTestPassed = false;
        _networkTestResult = '连接失败\n$e';
      });
    } finally {
      setState(() {
        _isTestingNetwork = false;
      });
    }
  }

  // ==================== ASR WebSocket 测试 ====================

  Future<void> _testAsrWebSocket() async {
    setState(() {
      _isTestingAsr = true;
      _asrTestResult = '正在连接 ASR WebSocket...';
      _asrTestPassed = null;
    });

    WebSocketChannel? channel;
    try {
      final apiKey = _getApiKey();
      final wsUri = Uri.parse('wss://dashscope.aliyuncs.com/api-ws/v1/inference');

      if (apiKey.isNotEmpty) {
        channel = IOWebSocketChannel.connect(wsUri, headers: {
          'Authorization': 'Bearer $apiKey',
        });
      } else {
        channel = WebSocketChannel.connect(wsUri);
      }

      // 等待连接就绪
      await channel.ready.timeout(const Duration(seconds: 10));

      setState(() {
        _asrTestResult = 'WebSocket 已连接\n正在验证 ASR 协议...';
      });

      // 发送 run-task 验证
      final taskId = 'test-${DateTime.now().millisecondsSinceEpoch}';
      final msg = jsonEncode({
        'header': {
          'action': 'run-task',
          'task_id': taskId,
          'streaming': 'duplex',
        },
        'payload': {
          'task_group': 'audio',
          'task': 'asr',
          'function': 'recognition',
          'model': 'fun-asr-realtime',
          'parameters': {
            'format': 'pcm',
            'sample_rate': 16000,
          },
          'input': {},
        },
      });

      channel.sink.add(msg);

      // 等待服务端响应
      bool gotResponse = false;
      final sub = channel.stream.listen(
        (message) {
          gotResponse = true;
          final data = jsonDecode(message.toString());
          final event = data['header']?['event'] ?? data['header']?['action'];
          setState(() {
            _asrTestPassed = true;
            _asrTestResult = 'ASR 连接正常\n协议验证成功\n服务端响应: $event';
          });
        },
        onError: (error) {
          setState(() {
            _asrTestPassed = false;
            _asrTestResult = 'ASR 协议错误\n$error';
          });
        },
      );

      // 等待 3 秒看是否有响应
      await Future.delayed(const Duration(seconds: 3));
      await sub.cancel();

      if (!gotResponse && _asrTestPassed == null) {
        setState(() {
          _asrTestPassed = false;
          _asrTestResult = 'ASR 服务无响应\n连接已建立但未收到协议确认';
        });
      }

      // 发送 finish-task
      try {
        channel.sink.add(jsonEncode({
          'header': {'action': 'finish-task', 'task_id': taskId},
          'payload': {},
        }));
      } catch (_) {}
    } on TimeoutException {
      setState(() {
        _asrTestPassed = false;
        _asrTestResult = 'WebSocket 连接超时\n请检查网络或 API Key';
      });
    } catch (e) {
      setState(() {
        _asrTestPassed = false;
        _asrTestResult = 'ASR 连接失败\n$e';
      });
    } finally {
      try {
        await channel?.sink.close();
      } catch (_) {}
      setState(() {
        _isTestingAsr = false;
      });
    }
  }

  // ==================== LLM API 测试 ====================

  Future<void> _testLLMApi() async {
    setState(() {
      _isTestingLLM = true;
      _llmTestResult = '正在测试 LLM API...';
      _llmTestPassed = null;
    });

    try {
      final apiKey = _getApiKey();
      final response = await http.post(
        Uri.parse('https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'qwen3.5-plus',
          'messages': [
            {'role': 'user', 'content': '你好，请回复"测试成功"四个字'}
          ],
          'max_tokens': 20,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] ?? '';
        setState(() {
          _llmTestPassed = true;
          _llmTestResult = 'LLM API 正常\n模型响应: $content';
        });
      } else {
        setState(() {
          _llmTestPassed = false;
          _llmTestResult = 'API 请求失败\n状态码: ${response.statusCode}\n${response.body.substring(0, response.body.length.clamp(0, 200))}';
        });
      }
    } on TimeoutException {
      setState(() {
        _llmTestPassed = false;
        _llmTestResult = 'API 请求超时\n请检查网络';
      });
    } catch (e) {
      setState(() {
        _llmTestPassed = false;
        _llmTestResult = 'API 测试失败\n$e';
      });
    } finally {
      setState(() {
        _isTestingLLM = false;
      });
    }
  }

  // ==================== 工具方法 ====================

  String _getApiKey() {
    // 优先使用用户配置的 key，其次使用 assets 默认 key
    if (_userApiKey != null && _userApiKey!.isNotEmpty) {
      return _userApiKey!;
    }
    return _cachedApiKey ?? '';
  }

  static String? _cachedApiKey;
  String? _userApiKey;

  Future<void> _loadApiKey() async {
    try {
      // 从用户保存的配置中读取 API Key
      final userModels = await ConfigService.loadASRModels();
      if (userModels.isNotEmpty) {
        // 找到第一个有 key 的模型
        for (final model in userModels) {
          if (model.key.isNotEmpty) {
            _userApiKey = model.key;
            return;
          }
        }
      }
      // 也检查 summary models
      final summaryModels = await ConfigService.loadSummaryModels();
      if (summaryModels.isNotEmpty && summaryModels[0].key.isNotEmpty) {
        _userApiKey = summaryModels[0].key;
        return;
      }
      // 回退到 assets/config.json
      final jsonString = await rootBundle.loadString('assets/config.json');
      final data = jsonDecode(jsonString);
      final models = data['summary_models'] as List?;
      if (models != null && models.isNotEmpty) {
        _cachedApiKey = models[0]['key'] ?? '';
      }
    } catch (_) {}
  }

  Future<void> _loadStorageConfig() async {
    final s3 = await ConfigService.loadS3Config();
    final webdav = await ConfigService.loadWebDAVConfig();
    setState(() {
      _s3Config = s3;
      _webdavConfig = webdav;
    });
  }

  // ==================== S3 测试 ====================

  Future<void> _testS3() async {
    setState(() {
      _isTestingS3 = true;
      _s3TestResult = '正在测试 S3 连接...';
      _s3TestPassed = null;
    });

    try {
      final result = await _storageService.testS3Connection(_s3Config);
      setState(() {
        _s3TestPassed = true;
        _s3TestResult = result;
      });
    } catch (e) {
      setState(() {
        _s3TestPassed = false;
        _s3TestResult = 'S3 连接失败\n$e';
      });
    } finally {
      setState(() => _isTestingS3 = false);
    }
  }

  // ==================== WebDAV 测试 ====================

  Future<void> _testWebDAV() async {
    setState(() {
      _isTestingWebDAV = true;
      _webdavTestResult = '正在测试 WebDAV 连接...';
      _webdavTestPassed = null;
    });

    try {
      final result = await _storageService.testWebDAVConnection(_webdavConfig);
      setState(() {
        _webdavTestPassed = true;
        _webdavTestResult = result;
      });
    } catch (e) {
      setState(() {
        _webdavTestPassed = false;
        _webdavTestResult = 'WebDAV 连接失败\n$e';
      });
    } finally {
      setState(() => _isTestingWebDAV = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统检测'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 麦克风测试卡片
            _buildTestCard(
              title: '麦克风测试',
              icon: Icons.mic,
              child: _buildMicTestSection(theme),
            ),
            const SizedBox(height: 16),

            // 网络连接测试卡片
            _buildTestCard(
              title: '网络连接测试',
              icon: Icons.wifi,
              child: _buildNetworkTestSection(theme),
            ),
            const SizedBox(height: 16),

            // ASR WebSocket 测试卡片
            _buildTestCard(
              title: 'ASR 语音识别测试',
              icon: Icons.record_voice_over,
              child: _buildAsrTestSection(theme),
            ),
            const SizedBox(height: 16),

            // LLM API 测试卡片
            _buildTestCard(
              title: 'LLM 大模型测试',
              icon: Icons.smart_toy,
              child: _buildLLMTestSection(theme),
            ),
            const SizedBox(height: 16),

            // S3 测试卡片
            _buildTestCard(
              title: 'S3 / OSS 存储测试',
              icon: Icons.cloud_upload,
              child: _buildS3TestSection(theme),
            ),
            const SizedBox(height: 16),

            // WebDAV 测试卡片
            _buildTestCard(
              title: 'WebDAV 存储测试',
              icon: Icons.folder_shared,
              child: _buildWebDAVTestSection(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  // 麦克风测试部分
  Widget _buildMicTestSection(ThemeData theme) {
    return Column(
      children: [
        // 录音状态指示
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _isRecording
                ? theme.colorScheme.error
                : theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isRecording ? Icons.mic : Icons.mic_none,
            size: 40,
            color: _isRecording
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // 状态文本
        Text(
          _isRecording ? '录音中...' : '未录音',
          style: TextStyle(
            fontSize: 16,
            color: _isRecording ? theme.colorScheme.error : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        // 音频数据统计
        if (_isRecording || _audioDataCount > 0)
          Text(
            '接收 $_audioDataCount 个音频块 | ${(_totalBytes / 1024).toStringAsFixed(1)} KB',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),

        // 开始/停止按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _toggleRecording,
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            label: Text(_isRecording ? '停止录音' : '开始录音'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // 网络测试部分
  Widget _buildNetworkTestSection(ThemeData theme) {
    return Column(
      children: [
        if (_networkTestResult.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _networkTestPassed == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _networkTestPassed!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _networkTestResult,
              style: TextStyle(
                fontSize: 14,
                color: _networkTestPassed == null
                    ? theme.colorScheme.onSurface
                    : _networkTestPassed!
                        ? Colors.green.shade700
                        : Colors.red.shade700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isTestingNetwork ? null : _testNetwork,
            icon: _isTestingNetwork
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_isTestingNetwork ? '测试中...' : '测试网络连接'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ASR WebSocket 测试部分
  Widget _buildAsrTestSection(ThemeData theme) {
    return Column(
      children: [
        if (_asrTestResult.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _asrTestPassed == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _asrTestPassed!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _asrTestResult,
              style: TextStyle(
                fontSize: 14,
                color: _asrTestPassed == null
                    ? theme.colorScheme.onSurface
                    : _asrTestPassed!
                        ? Colors.green.shade700
                        : Colors.red.shade700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isTestingAsr ? null : _testAsrWebSocket,
            icon: _isTestingAsr
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.record_voice_over),
            label: Text(_isTestingAsr ? '测试中...' : '测试 ASR WebSocket'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // LLM API 测试部分
  Widget _buildLLMTestSection(ThemeData theme) {
    return Column(
      children: [
        if (_llmTestResult.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _llmTestPassed == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _llmTestPassed!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _llmTestResult,
              style: TextStyle(
                fontSize: 14,
                color: _llmTestPassed == null
                    ? theme.colorScheme.onSurface
                    : _llmTestPassed!
                        ? Colors.green.shade700
                        : Colors.red.shade700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isTestingLLM ? null : _testLLMApi,
            icon: _isTestingLLM
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.smart_toy),
            label: Text(_isTestingLLM ? '测试中...' : '测试 LLM API'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // S3 测试部分
  Widget _buildS3TestSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 配置状态
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _s3Config.isConfigured
                ? 'Endpoint: ${_s3Config.endpoint.split('//').last.split('/').first}\nBucket: ${_s3Config.bucket}\nRegion: ${_s3Config.region.isEmpty ? "未设置" : _s3Config.region}'
                : '未配置 S3，请在设置中添加',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_s3TestResult.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _s3TestPassed == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _s3TestPassed!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _s3TestResult,
              style: TextStyle(
                fontSize: 14,
                color: _s3TestPassed == null
                    ? theme.colorScheme.onSurface
                    : _s3TestPassed!
                        ? Colors.green.shade700
                        : Colors.red.shade700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isTestingS3 || !_s3Config.isConfigured) ? null : _testS3,
            icon: _isTestingS3
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(_isTestingS3 ? '测试中...' : '测试 S3 连接'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // WebDAV 测试部分
  Widget _buildWebDAVTestSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 配置状态
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _webdavConfig.isConfigured
                ? 'URL: ${_webdavConfig.url}\n用户: ${_webdavConfig.username}'
                : '未配置 WebDAV，请在设置中添加',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_webdavTestResult.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _webdavTestPassed == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _webdavTestPassed!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _webdavTestResult,
              style: TextStyle(
                fontSize: 14,
                color: _webdavTestPassed == null
                    ? theme.colorScheme.onSurface
                    : _webdavTestPassed!
                        ? Colors.green.shade700
                        : Colors.red.shade700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isTestingWebDAV || !_webdavConfig.isConfigured) ? null : _testWebDAV,
            icon: _isTestingWebDAV
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_shared),
            label: Text(_isTestingWebDAV ? '测试中...' : '测试 WebDAV 连接'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
