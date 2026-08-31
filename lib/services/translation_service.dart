import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yanji/utils/config_loader.dart';

/// 翻译结果
class TranslationResult {
  final String originalText;
  final String translatedText;
  final bool isFinal;
  final String? speaker;

  const TranslationResult({
    required this.originalText,
    required this.translatedText,
    this.isFinal = true,
    this.speaker,
  });
}

/// 翻译显示模式
enum TranslationDisplayMode {
  original,   // 仅原文
  translated, // 仅译文
  bilingual,  // 双语对照
}

/// 支持的语言列表
class SupportedLanguage {
  final String code;
  final String name;
  final String nativeName;

  const SupportedLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });
}

const List<SupportedLanguage> kSupportedLanguages = [
  SupportedLanguage(code: 'zh', name: 'Chinese', nativeName: '中文'),
  SupportedLanguage(code: 'en', name: 'English', nativeName: 'English'),
  SupportedLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
  SupportedLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
  SupportedLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
  SupportedLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
  SupportedLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
  SupportedLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
  SupportedLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
  SupportedLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
  SupportedLanguage(code: 'th', name: 'Thai', nativeName: 'ไทย'),
  SupportedLanguage(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt'),
  SupportedLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
];

/// 多渠道机器翻译服务
///
/// 支持 DashScope、腾讯云、百度、网易有道、OpenAI 等翻译 API。
/// 只翻译 final 结果（完整句子），避免频繁调用。
class TranslationService {
  final TranslationConfig config;

  // 已翻译缓存（避免重复翻译相同文本）
  final Map<String, String> _cache = {};
  static const int _maxCacheSize = 200;

  TranslationService({required this.config});

  String get apiKey => config.apiKey;
  String get apiSecret => config.apiSecret;
  String get baseUrl => config.baseUrl;
  TranslationProviderType get provider => config.provider;

  bool get isConfigured => config.isConfigured;

  /// 翻译单段文本（根据 provider 自动选择对应 API）
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (text.trim().isEmpty) return '';
    if (sourceLanguage == targetLanguage) return text;

    // 检查缓存
    final cacheKey = '${config.provider.name}:$sourceLanguage:$targetLanguage:$text';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    String translated;
    try {
      switch (provider) {
        case TranslationProviderType.dashscope:
          translated = await _translateDashScope(text, sourceLanguage, targetLanguage);
          break;
        case TranslationProviderType.tencent:
          translated = await _translateTencent(text, sourceLanguage, targetLanguage);
          break;
        case TranslationProviderType.baidu:
          translated = await _translateBaidu(text, sourceLanguage, targetLanguage);
          break;
        case TranslationProviderType.netease:
          translated = await _translateNetease(text, sourceLanguage, targetLanguage);
          break;
        case TranslationProviderType.openai:
          translated = await _translateOpenAI(text, sourceLanguage, targetLanguage);
          break;
      }
    } catch (e) {
      debugPrint('[Translation] 翻译失败 (${provider.name}): $e');
      return text; // 失败返回原文
    }

    _addToCache(cacheKey, translated);
    return translated;
  }

  void _addToCache(String key, String value) {
    if (_cache.length >= _maxCacheSize) {
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }
    _cache[key] = value;
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      final result = await translate(
        text: '测试',
        sourceLanguage: 'zh',
        targetLanguage: 'en',
      );
      return result.isNotEmpty && result != '测试';
    } catch (e) {
      debugPrint('[Translation] 连接测试失败: $e');
      return false;
    }
  }

  void clearCache() {
    _cache.clear();
  }

  // ==================== DashScope 翻译 ====================

  Future<String> _translateDashScope(String text, String src, String tgt) async {
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'translate',
        'input': {
          'source_language': src,
          'target_language': tgt,
          'text': text,
        },
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final results = output?['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return results[0]['text'] as String? ?? text;
      }
    }
    throw Exception('DashScope API 错误: HTTP ${response.statusCode}');
  }

  // ==================== 腾讯云机器翻译 ====================

  Future<String> _translateTencent(String text, String src, String tgt) async {
    // 腾讯云 TMT API 需要 TC3-HMAC-SHA256 签名
    // 简化实现：使用 V3 签名
    final service = 'tmt';
    final action = 'TextTranslate';
    final version = '2018-03-21';
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final date = DateTime.now().toUtc().toString().substring(0, 10);

    final payload = jsonEncode({
      'SourceText': text,
      'Source': _tencentLangCode(src),
      'Target': _tencentLangCode(tgt),
      'ProjectId': 0,
    });

    // 计算 payload hash
    final payloadHash = sha256.convert(utf8.encode(payload)).toString();

    // 构建 canonical request
    final httpRequestMethod = 'POST';
    final canonicalUri = '/';
    final canonicalQueryString = '';
    final canonicalHeaders = 'content-type:application/json\nhost:${Uri.parse(baseUrl).host}\n';
    final signedHeaders = 'content-type;host';
    final canonicalRequest = '$httpRequestMethod\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

    // 计算签名
    final credentialScope = '$date/$service/tc3_request';
    final stringToSign = 'TC3-HMAC-SHA256\n$timestamp\n$credentialScope\n${sha256.convert(utf8.encode(canonicalRequest)).toString()}';

    final secretDate = Hmac(sha256, utf8.encode('TC3$apiKey')).convert(utf8.encode(date)).bytes;
    final secretService = Hmac(sha256, secretDate).convert(utf8.encode(service)).bytes;
    final secretSigning = Hmac(sha256, secretService).convert(utf8.encode('tc3_request')).bytes;
    final signature = Hmac(sha256, secretSigning).convert(utf8.encode(stringToSign)).toString();

    final authorization = 'TC3-HMAC-SHA256 Credential=$apiKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': authorization,
        'Content-Type': 'application/json',
        'Host': Uri.parse(baseUrl).host,
        'X-TC-Action': action,
        'X-TC-Version': version,
        'X-TC-Timestamp': timestamp.toString(),
      },
      body: payload,
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final responseObj = data['Response'] as Map<String, dynamic>?;
      if (responseObj != null) {
        final translated = responseObj['TargetText'] as String?;
        if (translated != null) return translated;
        final error = responseObj['Error'] as Map<String, dynamic>?;
        throw Exception('腾讯云 API 错误: ${error?['Message'] ?? '未知错误'}');
      }
    }
    throw Exception('腾讯云 API 错误: HTTP ${response.statusCode}');
  }

  String _tencentLangCode(String code) {
    // 腾讯云使用不同的语言代码
    const mapping = {
      'zh': 'zh',
      'en': 'en',
      'ja': 'ja',
      'ko': 'ko',
      'fr': 'fr',
      'de': 'de',
      'ru': 'ru',
      'es': 'es',
      'pt': 'pt',
      'it': 'it',
      'th': 'th',
      'vi': 'vi',
      'ar': 'ar',
    };
    return mapping[code] ?? code;
  }

  // ==================== 百度机器翻译 ====================

  Future<String> _translateBaidu(String text, String src, String tgt) async {
    // 百度翻译 API：https://fanyi-api.baidu.com/api/trans/vip/translate
    // 签名：MD5(appid + q + salt + secretKey)
    final salt = Random().nextInt(10000).toString();
    final sign = md5.convert(utf8.encode('$apiKey$text$salt$apiSecret')).toString();

    final params = {
      'q': text,
      'from': _baiduLangCode(src),
      'to': _baiduLangCode(tgt),
      'appid': apiKey, // 百度的 appid 作为 apiKey 使用
      'salt': salt,
      'sign': sign,
    };

    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error_code = data['error_code'] as String?;
      if (error_code != null && error_code != '52000') {
        throw Exception('百度 API 错误: ${data['error_msg']}');
      }
      final result = data['trans_result'] as List?;
      if (result != null && result.isNotEmpty) {
        return result[0]['dst'] as String? ?? text;
      }
    }
    throw Exception('百度 API 错误: HTTP ${response.statusCode}');
  }

  String _baiduLangCode(String code) {
    const mapping = {
      'zh': 'zh',
      'en': 'en',
      'ja': 'jp',
      'ko': 'kor',
      'fr': 'fra',
      'de': 'de',
      'ru': 'ru',
      'es': 'spa',
      'pt': 'pt',
      'it': 'it',
      'th': 'th',
      'vi': 'vie',
      'ar': 'ara',
    };
    return mapping[code] ?? code;
  }

  // ==================== 网易有道翻译 ====================

  Future<String> _translateNetease(String text, String src, String tgt) async {
    // 网易有道智云翻译 API
    // 签名：SHA256(appKey + input + salt + curtime + secret)
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    final curtime = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // input 截断处理：超过20字符时取前10+长度+后10
    String input;
    if (text.length > 20) {
      input = '${text.substring(0, 10)}${text.length}${text.substring(text.length - 10)}';
    } else {
      input = text;
    }

    final signStr = '$apiKey$input$salt$curtime$apiSecret';
    final sign = sha256.convert(utf8.encode(signStr)).toString();

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'q': text,
        'from': _neteaseLangCode(src),
        'to': _neteaseLangCode(tgt),
        'appKey': apiKey,
        'salt': salt,
        'sign': sign,
        'signType': 'v3',
        'curtime': curtime,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = data['errorCode'] as String?;
      if (errorCode != '0') {
        throw Exception('有道 API 错误: ${data['msg'] ?? errorCode}');
      }
      final translation = data['translation'] as List?;
      if (translation != null && translation.isNotEmpty) {
        return translation[0]['translated'] as String? ?? text;
      }
    }
    throw Exception('有道 API 错误: HTTP ${response.statusCode}');
  }

  String _neteaseLangCode(String code) {
    const mapping = {
      'zh': 'zh-CHS',
      'en': 'en',
      'ja': 'ja',
      'ko': 'ko',
      'fr': 'fr',
      'de': 'de',
      'ru': 'ru',
      'es': 'es',
      'pt': 'pt',
      'it': 'it',
      'th': 'th',
      'vi': 'vi',
      'ar': 'ar',
    };
    return mapping[code] ?? code;
  }

  // ==================== OpenAI 兼容翻译 ====================

  Future<String> _translateOpenAI(String text, String src, String tgt) async {
    final srcName = kSupportedLanguages.firstWhere(
      (l) => l.code == src, orElse: () => SupportedLanguage(code: src, name: src, nativeName: src),
    ).name;
    final tgtName = kSupportedLanguages.firstWhere(
      (l) => l.code == tgt, orElse: () => SupportedLanguage(code: tgt, name: tgt, nativeName: tgt),
    ).name;

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content': 'You are a professional translator. Translate the following text from $srcName to $tgtName. Output ONLY the translated text, no explanations.',
          },
          {
            'role': 'user',
            'content': text,
          },
        ],
        'temperature': 0.3,
        'max_tokens': 2048,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final content = choices[0]['message']?['content'] as String?;
        if (content != null) return content.trim();
      }
    }
    throw Exception('OpenAI API 错误: HTTP ${response.statusCode}');
  }
}
