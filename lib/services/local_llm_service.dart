import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:fllama/fllama.dart';

/// 本地 LLM 推理服务（基于 fllama / llama.cpp）
class LocalLlmService {
  String? _modelPath;
  String? _contextId;
  bool _isLoaded = false;
  bool _isGenerating = false;

  bool get isLoaded => _isLoaded;
  bool get isGenerating => _isGenerating;
  String? get modelPath => _modelPath;

  /// 加载 GGUF 模型
  Future<bool> loadModel(String modelPath) async {
    if (_isLoaded && _modelPath == modelPath) {
      debugPrint('[LocalLlm] 模型已加载: $modelPath');
      return true;
    }

    try {
      _modelPath = modelPath;

      // 查找 .gguf 文件
      final ggufFile = _findGGUF(modelPath);
      if (ggufFile == null) {
        debugPrint('[LocalLlm] 未找到 .gguf 文件: $modelPath');
        return false;
      }

      debugPrint('[LocalLlm] 加载模型: ${ggufFile.path}');
      debugPrint('[LocalLlm] 文件大小: ${(ggufFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB');

      final context = await Fllama.instance()?.initContext(
        ggufFile.path,
        emitLoadProgress: true,
      );

      if (context != null && context['contextId'] != null) {
        _contextId = context['contextId'].toString();
        _isLoaded = _contextId != null && double.tryParse(_contextId!) != null && double.parse(_contextId!) > 0;

        if (_isLoaded) {
          debugPrint('[LocalLlm] 模型加载成功, contextId=$_contextId');
          // 监听 token 流
          Fllama.instance()?.onTokenStream?.listen((data) {
            // 处理在 generate 方法中
          });
          return true;
        }
      }

      debugPrint('[LocalLlm] 模型加载失败: context=$context');
      return false;
    } catch (e) {
      debugPrint('[LocalLlm] 加载模型异常: $e');
      _isLoaded = false;
      return false;
    }
  }

  /// 流式生成文本
  Stream<String> generate({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async* {
    if (!_isLoaded || _contextId == null) {
      throw Exception('模型未加载');
    }

    if (_isGenerating) {
      throw Exception('正在生成中');
    }

    _isGenerating = true;
    final contextId = double.parse(_contextId!);

    // 监听 token 流
    StreamSubscription? sub;
    sub = Fllama.instance()?.onTokenStream?.listen((data) {
      if (data['function'] == 'completion') {
        final token = data['result']?['token'] as String?;
        if (token != null) {
          // token 已在 buffer 中
        }
      }
    });

    try {
      // 启动生成
      final result = await Fllama.instance()?.completion(
        contextId,
        prompt: prompt,
        nPredict: maxTokens,
        temperature: temperature,
        topP: topP,
      );

      if (result != null) {
        final text = result['result']?['text'] as String? ?? '';
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } catch (e) {
      debugPrint('[LocalLlm] 生成异常: $e');
      rethrow;
    } finally {
      _isGenerating = false;
      sub?.cancel();
    }
  }

  /// 非流式生成文本
  Future<String> generateSync({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async {
    if (!_isLoaded || _contextId == null) {
      throw Exception('模型未加载');
    }

    if (_isGenerating) {
      throw Exception('正在生成中');
    }

    _isGenerating = true;
    final contextId = double.parse(_contextId!);

    try {
      final result = await Fllama.instance()?.completion(
        contextId,
        prompt: prompt,
        nPredict: maxTokens,
        temperature: temperature,
        topP: topP,
      );

      return result?['result']?['text'] as String? ?? '';
    } finally {
      _isGenerating = false;
    }
  }

  /// 停止生成
  void stop() {
    if (_contextId != null) {
      Fllama.instance()?.stopCompletion(contextId: double.parse(_contextId!));
      _isGenerating = false;
    }
  }

  /// 释放资源
  void dispose() {
    stop();
    if (_contextId != null) {
      Fllama.instance()?.releaseContext(double.parse(_contextId!));
    }
    _isLoaded = false;
    _contextId = null;
    _modelPath = null;
    debugPrint('[LocalLlm] 资源已释放');
  }

  /// 查找 .gguf 文件（递归搜索）
  File? _findGGUF(String basePath) {
    final dir = Directory(basePath);
    if (!dir.existsSync()) return null;

    // 直接在当前目录查找
    for (final f in dir.listSync()) {
      if (f is File && f.path.endsWith('.gguf')) {
        return f;
      }
    }

    // 递归搜索子目录（最多 2 层）
    for (final f in dir.listSync()) {
      if (f is Directory) {
        for (final sf in f.listSync()) {
          if (sf is File && sf.path.endsWith('.gguf')) {
            return sf;
          }
        }
      }
    }

    return null;
  }
}

/// LLM 服务接口（统一云端和本地）
abstract class LlmProvider {
  Future<String> summarize(String transcript, {String? title, List<String>? participants, String? template});
  Stream<String> summarizeStream(String transcript, {String? title, List<String>? participants, String? template});
  void dispose();
}

/// 本地 LLM 服务
class LocalLlmProvider implements LlmProvider {
  final LocalLlmService _service;
  final String _systemPrompt;

  LocalLlmProvider({
    required LocalLlmService service,
    String systemPrompt = '你是一个专业的会议纪要助手。请根据提供的会议转录内容生成结构化的会议纪要。',
  })  : _service = service,
        _systemPrompt = systemPrompt;

  @override
  Future<String> summarize(String transcript, {String? title, List<String>? participants, String? template}) async {
    final participantStr = participants?.join('、') ?? '未指定';
    final prompt = '${template ?? _systemPrompt}\n\n会议标题：${title ?? '未命名会议'}\n参会人员：$participantStr\n\n转录内容：\n$transcript\n\n请根据以上内容生成会议纪要：';

    return await _service.generateSync(prompt: prompt, maxTokens: 4096, temperature: 0.3);
  }

  @override
  Stream<String> summarizeStream(String transcript, {String? title, List<String>? participants, String? template}) async* {
    final participantStr = participants?.join('、') ?? '未指定';
    final prompt = '${template ?? _systemPrompt}\n\n会议标题：${title ?? '未命名会议'}\n参会人员：$participantStr\n\n转录内容：\n$transcript\n\n请根据以上内容生成会议纪要：';

    yield* _service.generate(prompt: prompt, maxTokens: 4096, temperature: 0.3);
  }

  @override
  void dispose() {
    _service.dispose();
  }
}
