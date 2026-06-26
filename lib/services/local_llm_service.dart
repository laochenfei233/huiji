import 'dart:async';
import 'package:flutter/foundation.dart';

import 'local_llm_service_native.dart'
    if (dart.library.html) 'local_llm_service_web.dart';

export 'local_llm_service_native.dart'
    if (dart.library.html) 'local_llm_service_web.dart';

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
