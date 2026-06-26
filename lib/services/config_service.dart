import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/services/secure_storage_service.dart';
import 'package:yanji/utils/config_loader.dart';

class ConfigService {
  static const String _asrModelsKey = 'asr_models';
  static const String _summaryModelsKey = 'summary_models';
  static const String _s3ConfigKey = 's3_config';
  static const String _webdavConfigKey = 'webdav_config';
  static const String _githubProxyKey = 'github_proxy';

  // Load GitHub proxy setting
  static Future<String?> loadGithubProxy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_githubProxyKey);
  }

  // Save GitHub proxy setting
  static Future<void> saveGithubProxy(String? proxy) async {
    final prefs = await SharedPreferences.getInstance();
    if (proxy == null || proxy.isEmpty) {
      await prefs.remove(_githubProxyKey);
    } else {
      await prefs.setString(_githubProxyKey, proxy);
    }
  }

  // Load user-configured ASR models (keys loaded from secure storage)
  static Future<List<ASRModelConfig>> loadASRModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_asrModelsKey);

    List<ASRModelConfig> models = [];
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = json.decode(jsonString);
        models = jsonList
            .map((item) => ASRModelConfig.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return [];
      }
    }

    // 从安全存储加载 API Key 并合并
    final mergedModels = <ASRModelConfig>[];
    for (final model in models) {
      final secureKey = await SecureStorageService.loadASRKey(model.name);
      mergedModels.add(ASRModelConfig(
        name: model.name,
        type: model.type,
        url: model.url,
        key: secureKey.isNotEmpty ? secureKey : model.key,
        modelName: model.modelName,
        protocol: model.protocol,
        httpAsrIntervalSec: model.httpAsrIntervalSec,
        modelPath: model.modelPath,
      ));
    }

    return mergedModels;
  }

  // Save ASR models (keys stripped before saving to SharedPreferences)
  static Future<void> saveASRModels(List<ASRModelConfig> models) async {
    final prefs = await SharedPreferences.getInstance();

    // 将 API Key 存入安全存储，从模型配置中移除
    for (final model in models) {
      if (model.key.isNotEmpty) {
        await SecureStorageService.saveASRKey(model.name, model.key);
      }
    }

    final safeModels = models.map((model) => ASRModelConfig(
      name: model.name,
      type: model.type,
      url: model.url,
      key: '',
      modelName: model.modelName,
      protocol: model.protocol,
      httpAsrIntervalSec: model.httpAsrIntervalSec,
      modelPath: model.modelPath,
    )).toList();

    final jsonString = json.encode(
      safeModels.map((model) => model.toJson()).toList(),
    );
    await prefs.setString(_asrModelsKey, jsonString);
  }

  // Load user-configured summary models (keys loaded from secure storage)
  static Future<List<SummaryModelConfig>> loadSummaryModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_summaryModelsKey);

    List<SummaryModelConfig> models = [];
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = json.decode(jsonString);
        models = jsonList
            .map((item) => SummaryModelConfig.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return [];
      }
    }

    // 从安全存储加载 API Key 并合并
    final mergedModels = <SummaryModelConfig>[];
    for (final model in models) {
      final secureKey = await SecureStorageService.loadSummaryKey(model.name);
      mergedModels.add(SummaryModelConfig(
        name: model.name,
        url: model.url,
        key: secureKey.isNotEmpty ? secureKey : model.key,
        modelName: model.modelName,
      ));
    }

    return mergedModels;
  }

  // Save summary models (keys stripped before saving to SharedPreferences)
  static Future<void> saveSummaryModels(List<SummaryModelConfig> models) async {
    final prefs = await SharedPreferences.getInstance();

    for (final model in models) {
      if (model.key.isNotEmpty) {
        await SecureStorageService.saveSummaryKey(model.name, model.key);
      }
    }

    final safeModels = models.map((model) => SummaryModelConfig(
      name: model.name,
      url: model.url,
      key: '',
      modelName: model.modelName,
    )).toList();

    final jsonString = json.encode(
      safeModels.map((model) => model.toJson()).toList(),
    );
    await prefs.setString(_summaryModelsKey, jsonString);
  }

  // Load S3 configuration (credentials loaded from secure storage)
  static Future<S3Config> loadS3Config() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_s3ConfigKey);

    S3Config baseConfig = S3Config();
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        baseConfig = S3Config.fromJson(jsonMap);
      } catch (e) {
        return S3Config();
      }
    }

    // 从安全存储加载凭证
    final accessKey = await SecureStorageService.loadS3AccessKey();
    final secretKey = await SecureStorageService.loadS3SecretKey();

    return S3Config(
      endpoint: baseConfig.endpoint,
      bucket: baseConfig.bucket,
      region: baseConfig.region,
      accessKey: accessKey.isNotEmpty ? accessKey : baseConfig.accessKey,
      secretKey: secretKey.isNotEmpty ? secretKey : baseConfig.secretKey,
      usePathStyle: baseConfig.usePathStyle,
    );
  }

  // Save S3 configuration (credentials saved to secure storage)
  static Future<void> saveS3Config(S3Config config) async {
    final prefs = await SharedPreferences.getInstance();

    // 凭证存入安全存储
    if (config.accessKey.isNotEmpty || config.secretKey.isNotEmpty) {
      await SecureStorageService.saveS3Credentials(
        accessKey: config.accessKey,
        secretKey: config.secretKey,
      );
    }

    // 非敏感字段存入 SharedPreferences
    final safeConfig = S3Config(
      endpoint: config.endpoint,
      bucket: config.bucket,
      region: config.region,
      usePathStyle: config.usePathStyle,
    );
    final jsonString = json.encode(safeConfig.toJson());
    await prefs.setString(_s3ConfigKey, jsonString);
  }

  // Load WebDAV configuration (password loaded from secure storage)
  static Future<WebDAVConfig> loadWebDAVConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_webdavConfigKey);

    WebDAVConfig baseConfig = WebDAVConfig();
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        baseConfig = WebDAVConfig.fromJson(jsonMap);
      } catch (e) {
        return WebDAVConfig();
      }
    }

    // 从安全存储加载密码
    final password = await SecureStorageService.loadWebDAVPassword();

    return WebDAVConfig(
      url: baseConfig.url,
      username: baseConfig.username,
      password: password.isNotEmpty ? password : baseConfig.password,
    );
  }

  // Save WebDAV configuration (password saved to secure storage)
  static Future<void> saveWebDAVConfig(WebDAVConfig config) async {
    final prefs = await SharedPreferences.getInstance();

    // 密码存入安全存储
    if (config.password.isNotEmpty) {
      await SecureStorageService.saveWebDAVPassword(config.password);
    }

    // 非敏感字段存入 SharedPreferences
    final safeConfig = WebDAVConfig(
      url: config.url,
      username: config.username,
    );
    final jsonString = json.encode(safeConfig.toJson());
    await prefs.setString(_webdavConfigKey, jsonString);
  }
}
