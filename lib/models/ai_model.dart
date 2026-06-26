const String kModelScopeRepo = 'laochenfei233/sherpa-onnx';

class AIModel {
  final String id;
  final String name;
  final String description;
  final int totalSizeBytes;
  final String type; // 'asr' or 'llm'
  final String repo;
  final List<ModelFileItem> files;
  final List<ModelFileItem> companionFiles;
  final List<String> platforms; // 'android', 'ios', 'windows', 'macos', 'web' — 空表示全平台

  const AIModel({
    required this.id,
    required this.name,
    required this.description,
    required this.totalSizeBytes,
    required this.type,
    this.repo = kModelScopeRepo,
    required this.files,
    this.companionFiles = const [],
    this.platforms = const [],
  });

  /// 当前平台是否支持下载
  bool isPlatformSupported(String currentPlatform) {
    if (platforms.isEmpty) return true;
    return platforms.contains(currentPlatform);
  }

  int get totalDownloadSize =>
      totalSizeBytes + companionFiles.fold(0, (sum, f) => sum + f.sizeBytes);

  String get totalSizeStr {
    final bytes = totalDownloadSize;
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}

class ModelFileItem {
  final String filename; // 仓库中的路径
  final int sizeBytes;

  const ModelFileItem({
    required this.filename,
    required this.sizeBytes,
  });
}

class LocalModel {
  final AIModel model;
  final String localPath;
  final bool isDownloaded;

  const LocalModel({
    required this.model,
    required this.localPath,
    required this.isDownloaded,
  });
}

/// 预定义的可下载模型列表
const List<AIModel> kAvailableModels = [
  AIModel(
    id: 'paraformer_large',
    name: 'Paraformer-Large (中文最强)',
    description: '阿里 Paraformer-Large，中文语音识别精度最高（WER~7.5%），约 230MB',
    totalSizeBytes: 235000000,
    type: 'asr',
    repo: 'laochenfei233/paraformer-sherpa',
    files: [
      ModelFileItem(filename: 'model.int8.onnx', sizeBytes: 235000000),
      ModelFileItem(filename: 'tokens.txt', sizeBytes: 107000),
    ],
  ),
  AIModel(
    id: 'sensevoice_int8',
    name: 'SenseVoice-Small int8',
    description: 'k2-fsa 官方 int8 量化版，中英日粤多语言，约 228MB',
    totalSizeBytes: 239075328,
    type: 'asr',
    repo: 'laochenfei233/sensevoice-small-sherpa',
    files: [
      ModelFileItem(filename: 'model.int8.onnx', sizeBytes: 239075328),
      ModelFileItem(filename: 'tokens.txt', sizeBytes: 315392),
    ],
  ),
  AIModel(
    id: 'sensevoice_small',
    name: 'SenseVoice-Small float32',
    description: '阿里 SenseVoice-Small，多语言语音识别，约 241MB（float32 版）',
    totalSizeBytes: 241216364,
    type: 'asr',
    repo: 'laochenfei233/sensevoice-small-sherpa',
    files: [
      ModelFileItem(filename: 'model.onnx', sizeBytes: 241216364),
      ModelFileItem(filename: 'tokens.txt', sizeBytes: 176674),
    ],
  ),
];

/// 预定义的可下载本地 LLM 模型
const List<AIModel> kAvailableLlmModels = [
  // === Tier 1: 6GB RAM 设备 (骁龙865 / iPhone 11+) ===
  AIModel(
    id: 'qwen3_0_6b',
    name: 'Qwen3-0.6B (轻量)',
    description: '通义千问3 0.6B，中文摘要，适合 6GB+ 设备，约 378MB',
    totalSizeBytes: 378300000,
    type: 'llm',
    repo: 'laochenfei233/qwen3-llm',
    files: [
      ModelFileItem(filename: 'Qwen3-0.6B-Q4_K_M.gguf', sizeBytes: 378300000),
    ],
  ),
  AIModel(
    id: 'deepseek_r1_1_5b',
    name: 'DeepSeek-R1 1.5B (推理强)',
    description: 'DeepSeek R1 蒸馏版 1.5B，数学/推理能力强，中文好，约 1066MB',
    totalSizeBytes: 1066000000,
    type: 'llm',
    repo: 'laochenfei233/deepseek-r1-llm',
    files: [
      ModelFileItem(filename: 'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf', sizeBytes: 1066000000),
    ],
  ),
  AIModel(
    id: 'gemma3_1b',
    name: 'Gemma 3 1B (备选)',
    description: 'Google Gemma3 1B，多语言，适合 6GB+ 设备，约 769MB',
    totalSizeBytes: 769000000,
    type: 'llm',
    repo: 'laochenfei233/gemma3-llm',
    files: [
      ModelFileItem(filename: 'gemma-3-1b-it-Q4_K_M.gguf', sizeBytes: 769000000),
    ],
  ),
  // === Tier 2: 8GB+ RAM 设备 (骁龙8 Gen2+ / iPhone 14+) ===
  AIModel(
    id: 'qwen3_1_7b',
    name: 'Qwen3-1.7B (推荐)',
    description: '通义千问3 1.7B，中文质量优秀，适合 8GB+ 设备，约 1056MB',
    totalSizeBytes: 1056100000,
    type: 'llm',
    repo: 'laochenfei233/qwen3-llm',
    files: [
      ModelFileItem(filename: 'Qwen3-1.7B-Q4_K_M.gguf', sizeBytes: 1056100000),
    ],
  ),
  AIModel(
    id: 'qwen3_4b',
    name: 'Qwen3-4B (高质量)',
    description: '通义千问3 4B，最强中文摘要，适合 8GB+ 高配设备，约 2382MB',
    totalSizeBytes: 2382000000,
    type: 'llm',
    repo: 'laochenfei233/qwen3-llm',
    files: [
      ModelFileItem(filename: 'Qwen3-4B-Q4_K_M.gguf', sizeBytes: 2382000000),
    ],
  ),
  AIModel(
    id: 'phi4_mini',
    name: 'Phi-4-mini (英文强)',
    description: '微软 Phi-4-mini 3.8B，推理能力强，英文优秀，约 2376MB',
    totalSizeBytes: 2376000000,
    type: 'llm',
    repo: 'laochenfei233/phi4-llm',
    files: [
      ModelFileItem(filename: 'Phi-4-mini-instruct-Q4_K_M.gguf', sizeBytes: 2376000000),
    ],
  ),
  AIModel(
    id: 'glm4_9b',
    name: 'GLM-4-9B (仅电脑端)',
    description: '智谱 GLM-4-9B-Chat，中文最强，仅支持电脑端（5.9GB，手机内存不足）',
    totalSizeBytes: 5965000000,
    type: 'llm',
    repo: 'laochenfei233/glm4-llm',
    platforms: ['windows', 'macos'],
    files: [
      ModelFileItem(filename: 'glm-4-9b-chat-Q4_K_M.gguf', sizeBytes: 5965000000),
    ],
  ),
];
