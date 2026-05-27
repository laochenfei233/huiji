# 修复代码 - asr_service_v2.dart

## 主要问题
当前文件第10行的API端点URL错误：
```dart
// ❌ 错误：使用了文本生成端点
final String _baseUrl = 'https://dashscope.aliyuncs.com/api-v1/services/aigc/text-generation';

// ✅ 正确：应该使用ASR音频转录端点
final String _baseUrl = 'https://dashscope.aliyuncs.com/api-v1/services/audio/asr/transcription';
```

## 修复后的完整代码

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:meeting_note/services/logging_service.dart';

// Qwen3 ASR 服务类 - 修复版本
class ASRService {
  final String _apiKey;
  final String _modelName;
  // ✅ 修复：使用正确的ASR API端点
  final String _baseUrl = 'https://dashscope.aliyuncs.com/api-v1/services/audio/asr/transcription';

  ASRService(this._apiKey, this._modelName);

  // 实现实时转录功能
  Stream<String> realTimeTranscription(
    Uint8List audioData,
    {String language = 'zh-CN', 
     int sampleRate = 16000,
     // 移除不支持的参数
     String? context,
     bool enablePunctuation = true, // 标点符号预测
     String format = 'pcm'} // 音频格式
  ) async* {
    try {
      print('Starting transcription with:');
      print('- URL: $_baseUrl');
      print('- Model: $_modelName');
      print('- Audio data length: ${audioData.length}');
      print('- Language: $language');
      print('- Sample rate: $sampleRate');
      
      // 发送音频数据到Qwen3-ASR模型
      final response = await _sendAudioToModel(audioData, 
        language: language, 
        sampleRate: sampleRate,
        enablePunctuation: enablePunctuation,
        format: format
      );
      
      print('API Response: $response');
      
      if (response['success'] == true) {
        final text = response['data']['text'];
        print('Transcription result: $text');
        yield text;
      } else {
        throw Exception('ASR request failed: ${response['message']}');
      }
    } catch (e, stackTrace) {
      print('Error in realTimeTranscription: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // 发送音频数据到模型 - 修复版本
  Future<Map<String, dynamic>> _sendAudioToModel(
    Uint8List audioData,
    {String language = 'zh-CN', 
     int sampleRate = 16000,
     bool enablePunctuation = true,
     String format = 'pcm'}
  ) async {
    try {
      print('Encoding audio data...');
      final audioBase64 = base64Encode(audioData);
      print('Audio data encoded successfully, length: ${audioBase64.length}');
      
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

      // ✅ 修复：使用正确的ASR API请求格式
      final body = {
        'model': _modelName,
        'input': {
          'audio': audioBase64,
        },
        'parameters': {
          'sample_rate': sampleRate,
          'language': language,
          'format': format,
          'enable_punctuation': enablePunctuation,
          // 移除不支持的参数：
          // 'enable_itn', 'enable_emotion', 'enable_noise_rejection', 
          // 'enable_singing_recognition', 'enable_language_detection'
        },
        // 移除不支持的context参数
      };

      print('Making request to: $_baseUrl');
      print('Headers: $headers');
      print('Body keys: ${body.keys.toList()}');

      final response = await Dio().post(
        _baseUrl, 
        options: Options(headers: headers), 
        data: body
      );
      
      print('Response status: ${response.statusCode}');
      print('Response data: ${response.data}');
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': {
            'text': response.data['output']['text'] ?? '',
          }
        };
      } else {
        throw Exception('ASR request failed with status: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('Error in _sendAudioToModel: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
```

## 关键修复点

1. **API端点修复**：从文本生成端点改为ASR转录端点
2. **请求格式修复**：移除不支持的参数，简化请求体
3. **错误处理增强**：添加更详细的日志和错误追踪
4. **响应解析修复**：正确解析ASR API的响应格式

## 建议的下一步操作

1. 更新 `lib/services/asr_service_v2.dart` 文件
2. 检查 `assets/config.json` 中的API密钥配置
3. 测试修复效果
4. 如需使用实时转录，考虑改用 `asr_service.dart` 中的WebSocket实现