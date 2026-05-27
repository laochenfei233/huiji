# 会议记录转录功能400错误详细分析与解决方案

## 🚨 错误根本原因分析

通过深入分析项目代码，我发现了导致400错误的**关键问题**：

### 1. **API端点URL完全错误**
**位置：** `lib/services/asr_service_v2.dart` 第10行
```dart
final String _baseUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation';
```
**问题：** 这是**文本生成服务**的端点，而不是ASR音频转录服务！
**正确端点：** `https://dashscope.aliyuncs.com/api-v1/services/audio/asr/transcription`

### 2. **请求参数格式不匹配**
当前的请求体格式与阿里云ASR API要求不符：
```dart
// 当前错误的请求格式
final body = {
  'model': _modelName,
  'input': {
    'audio': base64Encode(audioData),
    'language': language,
    'sample_rate': sampleRate,
  },
  'parameters': { /* ... */ },
};
```

**正确格式应该遵循阿里云ASR API规范**

### 3. **模型端点不一致**
项目使用了不同的API端点和参数组合，导致混乱：
- `asr_service_v2.dart` 使用错误的文本生成端点
- `asr_service.dart` 尝试使用正确的ASR端点
- 两者混用导致不可预测的行为

## 🔧 解决方案

### 方案1: 修复ASR Service V2（推荐）

**修改 `lib/services/asr_service_v2.dart`：**

1. **修正API端点URL**
```dart
final String _baseUrl = 'https://dashscope.aliyuncs.com/api-v1/services/audio/asr/transcription';
```

2. **修正请求体格式**
```dart
final body = {
  'model': _modelName,
  'input': {
    'audio': base64Encode(audioData),
  },
  'parameters': {
    'sample_rate': sampleRate,
    'language': language,
    'format': 'pcm',
    'enable_punctuation': enablePunctuation,
  },
};
```

3. **移除不支持的参数**
```dart
// 移除这些非ASR API支持的参数
// 'context', 'enableITN', 'enableEmotion', 'enableNoiseRejection', etc.
```

### 方案2: 统一使用asr_service.dart
项目实际上已经有了完整实现的 `asr_service.dart`，它包含：
- ✅ 正确的ASR API端点
- ✅ 完整的请求格式
- ✅ WebSocket实时转录支持
- ✅ 错误处理机制

### 方案3: 修复配置不匹配
检查 `assets/config.json` 中的URL是否与实际使用的端点一致。

## 🧪 调试建议

### 1. 添加详细日志
```dart
try {
  print('Request URL: $_baseUrl');
  print('Request Headers: $headers');
  print('Request Body: $body');
  final response = await Dio().post(_baseUrl, options: Options(headers: headers), data: body);
  print('Response Status: ${response.statusCode}');
  print('Response Data: ${response.data}');
} catch (e) {
  print('DioException: ${e}');
  print('Error Type: ${e.runtimeType}');
  rethrow;
}
```

### 2. 验证API密钥
确保 `config.json` 中的API密钥有效且有ASR服务权限。

### 3. 测试音频数据格式
确保音频数据符合阿里云ASR API要求：
- 格式：PCM WAV
- 采样率：16kHz或8kHz
- 位深度：16bit
- 编码：Base64

### 4. 验证模型名称
检查使用的模型名称是否在阿里云支持的ASR模型列表中。

## 📋 推荐行动步骤

1. **立即修复：** 更新 `asr_service_v2.dart` 中的API端点URL
2. **统一架构：** 确定使用哪个ASR服务实现
3. **完善错误处理：** 添加更详细的400错误处理
4. **测试验证：** 用小段音频数据测试修复效果
5. **配置优化：** 检查并更新配置文件

## ⚠️ 关键注意

- 阿里云ASR API不支持`context`、`enableITN`等参数
- 请求体格式必须严格按照API文档
- API密钥必须具备ASR服务权限
- 音频数据格式要求严格

这个400错误完全是由于API调用错误造成的，修复后应该能够正常工作。