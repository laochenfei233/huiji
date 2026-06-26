import 'dart:async';
import 'package:flutter/foundation.dart';

/// 本地 LLM 推理服务（基于 fllama / llama.cpp）
/// Web 平台不支持，提供空实现
class LocalLlmService {
  String? _modelPath;
  String? _contextId;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  bool get isGenerating => false;
  String? get modelPath => _modelPath;

  Future<bool> loadModel(String modelPath) async {
    debugPrint('[LocalLlm] Web 平台不支持本地 LLM 推理');
    return false;
  }

  Stream<String> generate({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async* {
    throw UnsupportedError('Web 平台不支持本地 LLM 推理');
  }

  Future<String> generateSync({
    required String prompt,
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
  }) async {
    throw UnsupportedError('Web 平台不支持本地 LLM 推理');
  }

  void stop() {}

  void dispose() {}
}
