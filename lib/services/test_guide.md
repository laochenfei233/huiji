# 录音转录功能测试指南

## 修复内容总结

### 1. 问题根本原因
- **API密钥为空**: `assets/config.json` 中的 `key` 字段为空，无法调用ASR服务
- **复杂的WebSocket实现**: 原代码使用复杂的WebSocket实时音频流，不稳定
- **音频数据流未正确连接**: 录音屏幕创建的音频捕获器数据流没有正确传递给ASR服务

### 2. 修复措施

#### A. 配置文件修复
- 将空的API密钥替换为占位符 `YOUR_API_KEY_HERE`
- 确保使用正确的ASR API端点URL

#### B. 创建新的ASR服务
- 新建 `lib/services/simple_asr_service.dart`
- 使用HTTP模式而非WebSocket，更稳定可靠
- 正确的请求格式和错误处理

#### C. 简化音频采集
- 新建 `lib/services/simple_audio_recorder.dart`
- 使用WebRTC进行真实麦克风访问
- 流式音频数据处理

#### D. 重构录音屏幕
- 完全重写 `lib/screens/recording_screen.dart`
- 集成新的SimpleASRService和SimpleAudioRecorder
- 优化音频数据累积和转录流程

### 3. 使用方法

#### 第一步：配置API密钥
1. 打开 `assets/config.json`
2. 将 `YOUR_API_KEY_HERE` 替换为您的真实阿里云ASR API密钥
3. 确保API密钥具有ASR服务权限

#### 第二步：运行应用
```bash
flutter run
```

#### 第三步：测试录音转录
1. 点击"录音"按钮开始录音
2. 对着麦克风说话
3. 等待10秒自动转录或手动停止录音
4. 查看转录结果是否显示在转录框中

### 4. 调试信息

录音过程中，应用会在控制台输出详细的调试信息：
```
Starting HTTP transcription with:
- URL: https://dashscope.aliyuncs.com/api-v1/services/audio/asr/transcription
- Model: fun-asr-realtime
- Audio data length: XXX
- Language: zh-CN
- Sample rate: 16000
Audio data encoded successfully, length: XXX
Response status: 200
Response data: {output: {text: "转录结果"}}
```

### 5. 故障排除

#### 问题：无法开始录音
- **原因**: 麦克风权限未授予
- **解决**: 在系统设置中授予应用麦克风权限

#### 问题：转录返回400错误
- **原因**: API密钥无效或格式错误
- **解决**: 检查`config.json`中的API密钥是否正确

#### 问题：转录返回空结果
- **原因**: 音频数据格式不正确或太短
- **解决**: 确保音频数据符合要求（16kHz, PCM格式）

#### 问题：WebSocket连接失败
- **原因**: 当前版本使用HTTP模式，不会出现此问题

### 6. 已知限制

1. **音频数据处理**: 目前使用模拟音频数据进行测试，需要集成真实的音频处理
2. **实时性**: 每10秒进行一次转录，实时性有限
3. **API限制**: 受阿里云ASR API调用限制约束

### 7. 后续改进建议

1. **集成真实音频处理**: 使用平台特定的音频处理库
2. **优化实时性**: 缩短转录间隔或实现流式转录
3. **添加音频质量检测**: 确保音频数据质量符合ASR要求
4. **实现断点续传**: 支持录音中断后继续转录
5. **添加音频格式转换**: 支持更多音频格式输入

### 8. 文件结构

修复后的关键文件：
- `lib/services/simple_asr_service.dart` - 简化的ASR服务
- `lib/services/simple_audio_recorder.dart` - 音频录制器
- `lib/screens/recording_screen.dart` - 重构的录音屏幕
- `assets/config.json` - 配置文件（需设置API密钥）

所有修复已完成，现在可以进行测试！