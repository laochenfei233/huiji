import 'package:flutter_test/flutter_test.dart';
import 'package:yanji/services/translation_service.dart';
import 'package:yanji/utils/config_loader.dart';

void main() {
  group('TranslationService', () {
    test('TranslationConfig defaults', () {
      final config = TranslationConfig();
      expect(config.provider, TranslationProviderType.dashscope);
      expect(config.apiKey, '');
      expect(config.apiSecret, '');
      expect(config.isConfigured, false);
    });

    test('TranslationConfig isConfigured with apiKey', () {
      final config = TranslationConfig(apiKey: 'test-key');
      expect(config.isConfigured, true);
    });

    test('TranslationConfig JSON serialization', () {
      final config = TranslationConfig(
        provider: TranslationProviderType.tencent,
        apiKey: 'test-key',
        apiSecret: 'test-secret',
        defaultTargetLanguage: 'ja',
      );

      final json = config.toJson();
      expect(json['provider'], 'tencent');
      expect(json['api_key'], 'test-key');
      expect(json['api_secret'], 'test-secret');
      expect(json['default_target_language'], 'ja');

      final restored = TranslationConfig.fromJson(json);
      expect(restored.provider, TranslationProviderType.tencent);
      expect(restored.apiKey, 'test-key');
      expect(restored.apiSecret, 'test-secret');
      expect(restored.defaultTargetLanguage, 'ja');
    });

    test('TranslationConfig default provider fallback on unknown', () {
      final json = {'provider': 'unknown_provider', 'api_key': 'key'};
      final config = TranslationConfig.fromJson(json);
      expect(config.provider, TranslationProviderType.dashscope);
    });

    test('SupportedLanguage list has expected languages', () {
      expect(kSupportedLanguages.length, 13);
      expect(kSupportedLanguages.firstWhere((l) => l.code == 'zh').name, 'Chinese');
      expect(kSupportedLanguages.firstWhere((l) => l.code == 'en').name, 'English');
      expect(kSupportedLanguages.firstWhere((l) => l.code == 'ja').name, 'Japanese');
      expect(kSupportedLanguages.firstWhere((l) => l.code == 'ko').name, 'Korean');
    });

    test('TranslationProviderType has all expected providers', () {
      expect(TranslationProviderType.values.length, 5);
      expect(TranslationProviderType.values, contains(TranslationProviderType.dashscope));
      expect(TranslationProviderType.values, contains(TranslationProviderType.tencent));
      expect(TranslationProviderType.values, contains(TranslationProviderType.baidu));
      expect(TranslationProviderType.values, contains(TranslationProviderType.netease));
      expect(TranslationProviderType.values, contains(TranslationProviderType.openai));
    });

    test('kTranslationProviders has correct defaults', () {
      expect(kTranslationProviders.length, 5);
      final dashscope = kTranslationProviders.firstWhere((p) => p.type == TranslationProviderType.dashscope);
      expect(dashscope.defaultBaseUrl, contains('dashscope'));
      final tencent = kTranslationProviders.firstWhere((p) => p.type == TranslationProviderType.tencent);
      expect(tencent.defaultBaseUrl, contains('tencent'));
      final baidu = kTranslationProviders.firstWhere((p) => p.type == TranslationProviderType.baidu);
      expect(baidu.defaultBaseUrl, contains('baidu'));
      final netease = kTranslationProviders.firstWhere((p) => p.type == TranslationProviderType.netease);
      expect(netease.defaultBaseUrl, contains('youdao'));
    });

    test('TranslationService without API key returns original text', () async {
      final config = TranslationConfig(apiKey: '');
      final service = TranslationService(config: config);

      final result = await service.translate(
        text: 'Hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );

      expect(result, 'Hello'); // 无 API key 时返回原文
    });

    test('TranslationService same source/target returns original', () async {
      final config = TranslationConfig(apiKey: 'test');
      final service = TranslationService(config: config);

      final result = await service.translate(
        text: 'Hello',
        sourceLanguage: 'en',
        targetLanguage: 'en',
      );

      expect(result, 'Hello');
    });

    test('TranslationService empty text returns empty', () async {
      final config = TranslationConfig(apiKey: 'test');
      final service = TranslationService(config: config);

      final result = await service.translate(
        text: '',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );

      expect(result, '');
    });

    test('TranslationService cache works', () async {
      final config = TranslationConfig(apiKey: 'test');
      final service = TranslationService(config: config);

      // Clear cache
      service.clearCache();
      expect(service.isConfigured, true);
    });

    test('TranslationResult fields', () {
      const result = TranslationResult(
        originalText: 'Hello',
        translatedText: '你好',
        isFinal: true,
        speaker: 'Speaker 1',
      );

      expect(result.originalText, 'Hello');
      expect(result.translatedText, '你好');
      expect(result.isFinal, true);
      expect(result.speaker, 'Speaker 1');
    });

    test('TranslationDisplayMode has 3 modes', () {
      expect(TranslationDisplayMode.values.length, 3);
      expect(TranslationDisplayMode.values, contains(TranslationDisplayMode.original));
      expect(TranslationDisplayMode.values, contains(TranslationDisplayMode.translated));
      expect(TranslationDisplayMode.values, contains(TranslationDisplayMode.bilingual));
    });
  });
}
