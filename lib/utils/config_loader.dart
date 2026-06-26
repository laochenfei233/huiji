import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yanji/services/config_service.dart';

class ConfigLoader {
  static Future<AppConfig> loadConfig() async {
    try {
      // Load default config from assets
      final jsonString = await rootBundle.loadString('assets/config.json');
      final jsonData = json.decode(jsonString);
      
      // Load user saved configurations
      final userASRModels = await ConfigService.loadASRModels();
      final userSummaryModels = await ConfigService.loadSummaryModels();
      final userS3Config = await ConfigService.loadS3Config();
      final userWebDAVConfig = await ConfigService.loadWebDAVConfig();
      
      final List<ASRModelConfig> asrModels = [];
      if (userASRModels.isNotEmpty) {
        // Use user configured models if available
        asrModels.addAll(userASRModels);
      } else if (jsonData['asr_models'] != null) {
        // Fallback to default models
        for (var model in jsonData['asr_models']) {
          asrModels.add(ASRModelConfig.fromJson(model));
        }
      }
      
      final List<LLMModelConfig> llmModels = [];
      if (userSummaryModels.isNotEmpty) {
        llmModels.addAll(userSummaryModels);
      } else if (jsonData['summary_models'] != null) {
        for (var model in jsonData['summary_models']) {
          llmModels.add(LLMModelConfig.fromJson(model));
        }
      }
      
      final StorageConfig storage = StorageConfig(
        s3: userS3Config.bucket.isNotEmpty ? userS3Config : 
             jsonData['storage'] != null && jsonData['storage']['s3'] != null 
             ? S3Config.fromJson(jsonData['storage']['s3']) 
             : S3Config(),
        webdav: userWebDAVConfig.url.isNotEmpty ? userWebDAVConfig : 
                jsonData['storage'] != null && jsonData['storage']['webdav'] != null 
                ? WebDAVConfig.fromJson(jsonData['storage']['webdav']) 
                : WebDAVConfig(),
      );
      
      return AppConfig(
        asrModels: asrModels,
        llmModels: llmModels,
        storage: storage,
        githubProxy: await ConfigService.loadGithubProxy(),
      );
    } catch (e) {
      return AppConfig(
        asrModels: [],
        llmModels: [],
        storage: StorageConfig(s3: S3Config(), webdav: WebDAVConfig()),
      );
    }
  }
}

class AppConfig {
  final List<ASRModelConfig> asrModels;
  final List<LLMModelConfig> llmModels;
  final StorageConfig storage;
  final String? githubProxy; // GitHub 代理加速 URL

  AppConfig({
    required this.asrModels,
    required this.llmModels,
    required this.storage,
    this.githubProxy,
  });

  // 向后兼容
  List<LLMModelConfig> get summaryModels => llmModels;
}

class StorageConfig {
  final S3Config s3;
  final WebDAVConfig webdav;
  
  StorageConfig({
    required this.s3,
    required this.webdav,
  });
  
  factory StorageConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return StorageConfig(
        s3: S3Config(),
        webdav: WebDAVConfig(),
      );
    }
    
    return StorageConfig(
      s3: S3Config.fromJson(json['s3']),
      webdav: WebDAVConfig.fromJson(json['webdav']),
    );
  }
}

class S3Config {
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
  final bool usePathStyle; // true=path style (OSS/MinIO), false=virtual-hosted

  S3Config({
    this.endpoint = '',
    this.bucket = '',
    this.region = '',
    this.accessKey = '',
    this.secretKey = '',
    this.usePathStyle = true,
  });

  bool get isConfigured => endpoint.isNotEmpty && bucket.isNotEmpty && accessKey.isNotEmpty;

  factory S3Config.fromJson(Map<String, dynamic>? json) {
    if (json == null) return S3Config();
    return S3Config(
      endpoint: json['endpoint'] ?? '',
      bucket: json['bucket'] ?? '',
      region: json['region'] ?? '',
      accessKey: json['accessKey'] ?? '',
      secretKey: json['secretKey'] ?? '',
      usePathStyle: json['usePathStyle'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'usePathStyle': usePathStyle,
  };
}

class WebDAVConfig {
  final String url;
  final String username;
  final String password;

  WebDAVConfig({
    this.url = '',
    this.username = '',
    this.password = '',
  });

  bool get isConfigured => url.isNotEmpty && username.isNotEmpty;

  factory WebDAVConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return WebDAVConfig();
    return WebDAVConfig(
      url: json['url'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
  };
}

class ASRModelConfig {
  final String name;
  final String type; // 'websocket', 'http', 'local_funasr', 'local_funasr_onnx'
  final String url;
  final String key;
  final String? modelName;
  final String? protocol; // WebSocket 协议路径
  final int httpAsrIntervalSec; // HTTP ASR 发送音频间隔（秒）
  final String? modelPath; // 本地 ONNX 模型路径

  ASRModelConfig({
    required this.name,
    this.type = 'http',
    required this.url,
    this.key = '',
    this.modelName,
    this.protocol,
    this.httpAsrIntervalSec = 3,
    this.modelPath,
  });

  factory ASRModelConfig.fromJson(Map<String, dynamic> json) {
    return ASRModelConfig(
      name: json['name'] ?? '',
      type: json['type'] ?? 'http',
      url: json['url'] ?? '',
      key: json['key'] ?? '',
      modelName: json['model_name'],
      protocol: json['protocol'],
      httpAsrIntervalSec: json['http_asr_interval_sec'] as int? ?? 3,
      modelPath: json['model_path'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'url': url,
      'key': key,
      'model_name': modelName,
      'protocol': protocol,
      'http_asr_interval_sec': httpAsrIntervalSec,
      'model_path': modelPath,
    };
  }
}

class LLMModelConfig {
  final String name;
  final String url;
  final String key;
  final String modelName;
  final String? modelPath; // 本地 GGUF 模型路径

  LLMModelConfig({
    required this.name,
    required this.url,
    required this.key,
    this.modelName = 'qwen3.5-plus',
    this.modelPath,
  });

  bool get isLocal => modelPath != null && modelPath!.isNotEmpty;

  factory LLMModelConfig.fromJson(Map<String, dynamic> json) {
    return LLMModelConfig(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      key: json['key'] ?? '',
      modelName: json['model_name'] ?? 'qwen3.5-plus',
      modelPath: json['model_path'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'key': key,
      'model_name': modelName,
      'model_path': modelPath,
    };
  }
}

// 向后兼容
typedef SummaryModelConfig = LLMModelConfig;