# 言记 (YanJi)

智能会议纪要系统 — 实时语音转写 + AI 摘要生成 + 多格式导出

## 功能特性

### 语音识别
- 基于 DashScope 百炼实时语音识别（FunASR / Qwen3 ASR）
- WebSocket 实时流式转写，边录边出文字
- 原生平台直连 DashScope，无需代理服务器

### 会议纪要
- AI 自动生成结构化会议纪要（基于 Qwen-Plus）
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
- ASR WebSocket 连接测试
- LLM API 连接测试
- S3 / WebDAV 连接测试

## 支持平台

| 平台 | 状态 |
|------|------|
| Android | 已支持 |
| Web | 已支持 |
| Windows | 已支持 |
| macOS | 待适配 |

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

### 摘要模型
- 选择摘要模型（默认：阿里云 Qwen-Plus）
- 填写 DashScope API Key

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
| Dio | HTTP 客户端 |
| WebSocket | 实时语音流 |
| DashScope API | 语音识别 + 大模型 |
| HyperOS 主题 | 小米设计风格 |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── database_init.dart           # 数据库初始化
├── models/                      # 数据模型
│   ├── meeting.dart             # 会议模型
│   ├── meeting_session.dart     # 会议会话模型
│   └── template.dart            # 模板模型
├── providers/                   # 状态管理
│   ├── meeting_provider.dart
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
│   ├── template_management_screen.dart
│   ├── audio_test_screen.dart   # 系统检测
│   └── log_viewer_screen.dart
├── services/                    # 业务服务
│   ├── storage_service.dart         # SQLite 存储
│   ├── asr_service.dart             # 语音识别 (WebSocket)
│   ├── llm_service.dart             # 大模型 API
│   ├── audio_recorder_service.dart  # 音频录制
│   ├── cloud_storage_service.dart   # S3 / WebDAV
│   ├── config_service.dart          # 配置持久化
│   └── template_service.dart        # 模板管理
├── utils/                       # 工具类
│   ├── theme_utils.dart         # HyperOS 主题
│   ├── config_loader.dart       # 配置加载
│   └── export_helper.dart       # 导出功能
└── widgets/                     # 通用组件
    └── sidebar.dart             # 侧边栏
```

## 主题设计

采用小米 HyperOS 设计语言：
- 主色：`#4A90D9`（浅色）/ `#6AB0F3`（深色）
- 背景：`#F7F7F7`（浅色）/ `#1A1A1A`（深色）
- 圆角卡片（16px）、无阴影、简洁配色
- 流畅的侧边栏滑动手势和动画

## ASR 协议

基于 DashScope 百炼 WebSocket 协议：
1. 建立 WebSocket 连接到 `wss://dashscope.aliyuncs.com/api-ws/v1/inference`
2. 发送 `run-task` 启动识别任务
3. 持续发送 PCM 音频数据（16kHz 16bit 单声道）
4. 接收 `result-generated` 实时识别结果
5. 发送 `finish-task` 结束任务

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
