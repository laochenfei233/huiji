# 言记 (YanJi)

智能会议纪要系统 — 实时语音转写 + AI 摘要生成 + 多格式导出

## 功能特性

### 语音识别
- **云端 ASR**：DashScope 百炼实时语音识别（FunASR / Qwen3 ASR）
- **本地 ASR**：sherpa-onnx 离线识别（SenseVoice-Small，无需联网）
- WebSocket 实时流式转写，边录边出文字
- 支持多 ASR 后端切换

### 会议纪要
- AI 自动生成结构化会议纪要
- **云端 LLM**：通义千问、DeepSeek、OpenAI 等兼容 API
- **本地 LLM**：基于 llama.cpp 的离线摘要生成（无需联网）
- 5 种内置模板：Executive 摘要、详细纪要、行动项清单、决策日志、问答整理
- 支持自定义模板，可设置默认模板
- 基于会议内容的智能问答

### 数据管理
- 会议历史列表，支持关键词搜索
- 会议数据本地 SQLite 持久化存储
- 详细数据统计（会议数、总字数、参与人数等）

### 导出功能
- Markdown (.md) 导出
- Word (.doc) 导出（HTML 格式，兼容 Microsoft Word）
- 一键复制到剪贴板
- 通过系统分享面板发送文件

### 云存储
- S3 / OSS 存储（支持阿里云 OSS、AWS S3、MinIO 等）
- WebDAV 存储（支持坚果云、NextCloud 等）
- 连接测试与状态检测

### 系统检测
- 麦克风录音测试
- 网络连接测试
- ASR 连接测试
- LLM API 连接测试
- S3 / WebDAV 连接测试

## 支持平台

| 平台 | 状态 |
|------|------|
| Android | 已支持 |
| Web | 已支持 |
| Windows | 已支持 |
| iOS | 待适配 |

## 本地模型

### 本地 ASR 模型

| 模型 | 大小 | 语言 | 说明 |
|------|------|------|------|
| SenseVoice-Small (float32) | 241MB | 中英日粤 | 阿里多语言语音识别 |

### 本地 LLM 模型

#### 6GB RAM 设备 (骁龙865 / iPhone 11+)

| 模型 | 参数量 | 大小 | 特点 |
|------|--------|------|------|
| Qwen3-0.6B | 0.6B | ~400MB | 中文轻量首选 |
| DeepSeek-R1 1.5B | 1.5B | ~800MB | 推理/数学能力强 |
| Gemma 3 1B | 1B | ~700MB | 多语言均衡 |

#### 8GB+ RAM 设备 (骁龙8 Gen2+ / iPhone 14+)

| 模型 | 参数量 | 大小 | 特点 |
|------|--------|------|------|
| Qwen3-1.7B | 1.7B | ~1GB | 中文质量最优 |
| Qwen3-4B | 4B | ~3.9GB | 最强中文摘要 |
| ChatGLM3-6B | 6B | ~3.8GB | 中文对话能力强 |
| Phi-4-mini | 3.8B | ~2.1GB | 英文/推理能力强 |

> 所有模型均为 GGUF Q4_K_M 量化格式，通过 fllama (llama.cpp) 在设备端推理。

## 快速开始

### 环境要求
- Flutter SDK >= 3.44.0
- Dart SDK >= 3.12.0
- Android SDK（如需构建 Android）
- Chrome（如需运行 Web）

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
# Android
flutter run

# Web
flutter run -d chrome

# Windows
flutter run -d windows
```

### 构建

```bash
# Android APK
flutter build apk --debug

# Windows
flutter build windows --debug

# Web
flutter build web
```

## 配置

首次使用前，在 **设置** 中配置以下内容：

### ASR 语音识别
- 选择识别模型（默认：百炼 FunASR Realtime）
- 填写 DashScope API Key
- 或选择本地模型（SenseVoice-Small，离线可用）

### LLM 模型
- 选择 LLM 模型（默认：阿里云 Qwen-Plus）
- 填写 API Key
- 或选择本地模型（Qwen3 / DeepSeek / Gemma 等，离线可用）

### 云存储（可选）
- S3 / OSS：填写 Endpoint、Bucket、Access Key、Secret Key
- WebDAV：填写 URL、用户名、密码

## 技术栈

| 技术 | 说明 |
|------|------|
| Flutter 3.44.0 | 跨平台 UI 框架 |
| Dart 3.12.0 | 开发语言 |
| SQLite (sqflite) | 本地数据库 |
| Provider | 状态管理 |
| WebSocket | 实时语音流 |
| DashScope API | 云端 ASR + LLM |
| sherpa-onnx | 本地 ASR 推理 |
| fllama (llama.cpp) | 本地 LLM 推理 |
| HyperOS 主题 | 小米设计风格 |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型
│   ├── meeting.dart             # 会议模型
│   ├── meeting_session.dart     # 会议会话模型
│   ├── ai_model.dart            # ASR/LLM 模型定义
│   └── template.dart            # 模板模型
├── providers/                   # 状态管理
│   └── meeting_session_provider.dart
├── screens/                     # 页面
│   ├── home_screen.dart         # 首页（侧边栏布局）
│   ├── meeting_list_screen.dart # 会议列表
│   ├── meeting_detail_screen.dart
│   ├── meeting_setup_screen.dart
│   ├── meeting_recording_screen.dart
│   ├── meeting_summary_screen.dart
│   ├── statistics_screen.dart   # 数据统计
│   ├── settings_screen.dart     # 设置
│   ├── model_management_screen.dart       # 本地 ASR 模型管理
│   ├── llm_model_management_screen.dart   # 本地 LLM 模型管理
│   ├── template_management_screen.dart
│   └── import_screen.dart       # 数据导入
├── services/                    # 业务服务
│   ├── asr_service.dart             # 语音识别（云端 + 本地）
│   ├── llm_service.dart             # LLM 服务（云端 API）
│   ├── local_llm_service.dart       # 本地 LLM 推理（fllama）
│   ├── model_download_service.dart  # ASR 模型下载
│   ├── llm_model_download_service.dart  # LLM 模型下载
│   ├── audio_recorder_service.dart  # 音频录制
│   ├── storage_service.dart         # SQLite 存储
│   ├── cloud_storage_service.dart   # S3 / WebDAV
│   ├── config_service.dart          # 配置持久化
│   ├── recording_notification_service.dart  # 录音通知
│   └── template_service.dart        # 模板管理
├── utils/                       # 工具类
│   ├── theme_utils.dart         # HyperOS 主题
│   ├── config_loader.dart       # 配置加载
│   └── export_helper.dart       # 导出功能
└── widgets/                     # 通用组件
    ├── sidebar.dart             # 侧边栏
    └── model_edit_dialog.dart   # 模型编辑对话框
```

## 主题设计

采用小米 HyperOS 设计语言：
- 主色：`#4A90D9`（浅色）/ `#6AB0F3`（深色）
- 背景：`#F7F7F7`（浅色）/ `#1A1A1A`（深色）
- 圆角卡片（16px）、无阴影、简洁配色
- 流畅的侧边栏滑动手势和动画

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

## License

MIT License

## 联系方式

- GitHub: [@laochenfei233](https://github.com/laochenfei233)
- 项目地址: [https://github.com/laochenfei233/meeting_note](https://github.com/laochenfei233/meeting_note)
