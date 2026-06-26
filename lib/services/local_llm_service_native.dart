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
  String? get modelPath => _modelPath;

  Future<bool> loadModel(String modelPath) async {
    if (_isLoaded && _modelPath == modelPath) return true;
    try {
      _modelPath = modelPath;
      final ggufFile = _findGGUF(modelPath);
      if (ggufFile == null) {
        debugPrint('[LocalLlm] 未找到 .gguf 文件: $modelPath');
        return false;
      }
      debugPrint('[LocalLlm] 加载模型: ${ggufFile.path} (${(ggufFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
      final context = await Fllama.instance()?.initContext(ggufFile.path, emitLoadProgress: true);
      if (context != null && context['contextId'] != null) {
        _contextId = context['contextId'].toString();
        _isLoaded = double.tryParse(_contextId!) != null && double.parse(_contextId!) > 0;
        if (_isLoaded) debugPrint('[LocalLlm] 模型加载成功');
        return _isLoaded;
      }
      return false;
    } catch (e) {
      debugPrint('[LocalLlm] 加载异常: $e');
      _isLoaded = false;
      return false;
    }
  }

  Stream<String> generate({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async* {
    if (!_isLoaded || _contextId == null) throw Exception('模型未加载');
    if (_isGenerating) throw Exception('正在生成中');
    _isGenerating = true;
    try {
      final result = await Fllama.instance()?.completion(
        double.parse(_contextId!), prompt: prompt, nPredict: maxTokens,
        temperature: temperature, topP: topP,
      );
      if (result != null) {
        final text = result['result']?['text'] as String? ?? '';
        if (text.isNotEmpty) yield text;
      }
    } finally {
      _isGenerating = false;
    }
  }

  Future<String> generateSync({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async {
    if (!_isLoaded || _contextId == null) throw Exception('模型未加载');
    if (_isGenerating) throw Exception('正在生成中');
    _isGenerating = true;
    try {
      final result = await Fllama.instance()?.completion(
        double.parse(_contextId!), prompt: prompt, nPredict: maxTokens,
        temperature: temperature, topP: topP,
      );
      return result?['result']?['text'] as String? ?? '';
    } finally {
      _isGenerating = false;
    }
  }

  void stop() {
    if (_contextId != null) {
      Fllama.instance()?.stopCompletion(contextId: double.parse(_contextId!));
      _isGenerating = false;
    }
  }

  void dispose() {
    stop();
    if (_contextId != null) Fllama.instance()?.releaseContext(double.parse(_contextId!));
    _isLoaded = false;
    _contextId = null;
    _modelPath = null;
  }

  File? _findGGUF(String basePath) {
    final dir = Directory(basePath);
    if (!dir.existsSync()) return null;
    for (final f in dir.listSync()) {
      if (f is File && f.path.endsWith('.gguf')) return f;
    }
    for (final f in dir.listSync()) {
      if (f is Directory) {
        for (final sf in f.listSync()) {
          if (sf is File && sf.path.endsWith('.gguf')) return sf;
        }
      }
    }
    return null;
  }
}
