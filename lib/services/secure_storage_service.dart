import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 安全存储服务 — 用于存储 API Key、密钥等敏感信息
/// 使用 flutter_secure_storage，底层使用 Keychain(iOS)/EncryptedSharedPreferences(Android)
class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const String _asrKeysPrefix = 'asr_key_';
  static const String _summaryKeysPrefix = 'summary_key_';
  static const String _s3SecretKey = 's3_secret';
  static const String _s3AccessKey = 's3_access';
  static const String _webdavPasswordKey = 'webdav_password';

  // ==================== ASR API Keys ====================

  static Future<void> saveASRKey(String modelName, String key) async {
    await _storage.write(key: '$_asrKeysPrefix$modelName', value: key);
  }

  static Future<String> loadASRKey(String modelName) async {
    return await _storage.read(key: '$_asrKeysPrefix$modelName') ?? '';
  }

  static Future<void> removeASRKey(String modelName) async {
    await _storage.delete(key: '$_asrKeysPrefix$modelName');
  }

  // ==================== Summary API Keys ====================

  static Future<void> saveSummaryKey(String modelName, String key) async {
    await _storage.write(key: '$_summaryKeysPrefix$modelName', value: key);
  }

  static Future<String> loadSummaryKey(String modelName) async {
    return await _storage.read(key: '$_summaryKeysPrefix$modelName') ?? '';
  }

  static Future<void> removeSummaryKey(String modelName) async {
    await _storage.delete(key: '$_summaryKeysPrefix$modelName');
  }

  // ==================== S3 Credentials ====================

  static Future<void> saveS3Credentials({required String accessKey, required String secretKey}) async {
    await _storage.write(key: _s3AccessKey, value: accessKey);
    await _storage.write(key: _s3SecretKey, value: secretKey);
  }

  static Future<String> loadS3AccessKey() async {
    return await _storage.read(key: _s3AccessKey) ?? '';
  }

  static Future<String> loadS3SecretKey() async {
    return await _storage.read(key: _s3SecretKey) ?? '';
  }

  static Future<void> removeS3Credentials() async {
    await _storage.delete(key: _s3AccessKey);
    await _storage.delete(key: _s3SecretKey);
  }

  // ==================== WebDAV Password ====================

  static Future<void> saveWebDAVPassword(String password) async {
    await _storage.write(key: _webdavPasswordKey, value: password);
  }

  static Future<String> loadWebDAVPassword() async {
    return await _storage.read(key: _webdavPasswordKey) ?? '';
  }

  static Future<void> removeWebDAVPassword() async {
    await _storage.delete(key: _webdavPasswordKey);
  }

  // ==================== Migration Helper ====================

  /// 从 SharedPreferences 迁移敏感数据到安全存储
  /// 迁移完成后删除 SharedPreferences 中的明文数据
  static Future<bool> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 迁移 ASR 模型 keys
      final asrModelsJson = prefs.getString('asr_models');
      if (asrModelsJson != null && asrModelsJson.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(asrModelsJson);
        for (final item in jsonList) {
          final map = item as Map<String, dynamic>;
          final name = map['name'] as String? ?? '';
          final key = map['key'] as String? ?? '';
          if (key.isNotEmpty) {
            await saveASRKey(name, key);
            // 清除明文 key
            map['key'] = '';
          }
        }
        // 保存不含 key 的模型列表回 SharedPreferences
        await prefs.setString('asr_models', json.encode(jsonList));
      }

      // 迁移 Summary 模型 keys
      final summaryModelsJson = prefs.getString('summary_models');
      if (summaryModelsJson != null && summaryModelsJson.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(summaryModelsJson);
        for (final item in jsonList) {
          final map = item as Map<String, dynamic>;
          final name = map['name'] as String? ?? '';
          final key = map['key'] as String? ?? '';
          if (key.isNotEmpty) {
            await saveSummaryKey(name, key);
            map['key'] = '';
          }
        }
        await prefs.setString('summary_models', json.encode(jsonList));
      }

      // 迁移 S3 配置
      final s3Json = prefs.getString('s3_config');
      if (s3Json != null && s3Json.isNotEmpty) {
        final map = json.decode(s3Json) as Map<String, dynamic>;
        final accessKey = map['accessKey'] as String? ?? '';
        final secretKey = map['secretKey'] as String? ?? '';
        if (accessKey.isNotEmpty || secretKey.isNotEmpty) {
          await saveS3Credentials(accessKey: accessKey, secretKey: secretKey);
          map['accessKey'] = '';
          map['secretKey'] = '';
          await prefs.setString('s3_config', json.encode(map));
        }
      }

      // 迁移 WebDAV 配置
      final webdavJson = prefs.getString('webdav_config');
      if (webdavJson != null && webdavJson.isNotEmpty) {
        final map = json.decode(webdavJson) as Map<String, dynamic>;
        final password = map['password'] as String? ?? '';
        if (password.isNotEmpty) {
          await saveWebDAVPassword(password);
          map['password'] = '';
          await prefs.setString('webdav_config', json.encode(map));
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}
