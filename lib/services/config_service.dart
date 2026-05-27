import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/utils/config_loader.dart';

class ConfigService {
  static const String _asrModelsKey = 'asr_models';
  static const String _summaryModelsKey = 'summary_models';
  static const String _s3ConfigKey = 's3_config';
  static const String _webdavConfigKey = 'webdav_config';

  // Load user-configured ASR models
  static Future<List<ASRModelConfig>> loadASRModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_asrModelsKey);
    
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = json.decode(jsonString);
        return jsonList
            .map((item) => ASRModelConfig.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // If parsing fails, return empty list
        return [];
      }
    }
    
    // Return empty list if no saved models
    return [];
  }

  // Save ASR models
  static Future<void> saveASRModels(List<ASRModelConfig> models) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(
      models.map((model) => model.toJson()).toList(),
    );
    await prefs.setString(_asrModelsKey, jsonString);
  }

  // Load user-configured summary models
  static Future<List<SummaryModelConfig>> loadSummaryModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_summaryModelsKey);
    
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = json.decode(jsonString);
        return jsonList
            .map((item) => SummaryModelConfig.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // If parsing fails, return empty list
        return [];
      }
    }
    
    // Return empty list if no saved models
    return [];
  }

  // Save summary models
  static Future<void> saveSummaryModels(List<SummaryModelConfig> models) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(
      models.map((model) => model.toJson()).toList(),
    );
    await prefs.setString(_summaryModelsKey, jsonString);
  }

  // Load S3 configuration
  static Future<S3Config> loadS3Config() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_s3ConfigKey);
    
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        return S3Config.fromJson(jsonMap);
      } catch (e) {
        // If parsing fails, return default config
        return S3Config();
      }
    }
    
    // Return default config if none saved
    return S3Config(bucket: '', region: '');
  }

  // Save S3 configuration
  static Future<void> saveS3Config(S3Config config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(config.toJson());
    await prefs.setString(_s3ConfigKey, jsonString);
  }

  // Load WebDAV configuration
  static Future<WebDAVConfig> loadWebDAVConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_webdavConfigKey);
    
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        return WebDAVConfig.fromJson(jsonMap);
      } catch (e) {
        // If parsing fails, return default config
        return WebDAVConfig();
      }
    }
    
    // Return default config if none saved
    return WebDAVConfig(url: '', username: '');
  }

  // Save WebDAV configuration
  static Future<void> saveWebDAVConfig(WebDAVConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(config.toJson());
    await prefs.setString(_webdavConfigKey, jsonString);
  }
}