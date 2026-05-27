import 'package:flutter/material.dart';
import 'package:yanji/main.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/services/config_service.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/screens/template_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<AppConfig> _configFuture;
  bool _darkMode = false;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _configFuture = ConfigLoader.loadConfig();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _darkMode);
    await prefs.setBool('notifications_enabled', _notificationsEnabled);
  }

  // Function to show dialog for editing ASR model
  void _editASRModel(BuildContext context, ASRModelConfig model, int index) async {
    final nameController = TextEditingController(text: model.name);
    final urlController = TextEditingController(text: model.url);
    final keyController = TextEditingController(text: model.key);
    final modelNameController = TextEditingController(text: model.modelName ?? '');
    final protocolController = TextEditingController(text: model.protocol ?? '');
    String modelType = model.type;
    int httpAsrInterval = model.httpAsrIntervalSec;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('编辑 ASR 模型 - ${model.name}'),
              content: SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '名称'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: modelType,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(value: 'websocket', child: Text('WebSocket（百炼实时流式）')),
                          DropdownMenuItem(value: 'local_funasr', child: Text('本地 FunASR（paraformer-zh-streaming）')),
                          DropdownMenuItem(value: 'http', child: Text('HTTP API')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            modelType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (modelType == 'websocket') ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'WebSocket 服务地址',
                            hintText: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: keyController,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'fun-asr-realtime',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: protocolController,
                          decoration: const InputDecoration(
                            labelText: '协议路径（可选）',
                            hintText: '/ws',
                          ),
                        ),
                      ] else if (modelType == 'local_funasr') ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'WebSocket 服务地址',
                            hintText: 'ws://localhost:10095',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'paraformer-zh-streaming',
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'API 地址',
                            hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: keyController,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'qwen-audio-turbo',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: httpAsrInterval,
                          decoration: const InputDecoration(labelText: '音频发送间隔'),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 秒')),
                            DropdownMenuItem(value: 5, child: Text('5 秒')),
                            DropdownMenuItem(value: 10, child: Text('10 秒')),
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                            DropdownMenuItem(value: 60, child: Text('1 分钟')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                httpAsrInterval = value;
                              });
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final config = await _configFuture;
                    final updatedModels = List<ASRModelConfig>.from(config.asrModels);
                    updatedModels[index] = ASRModelConfig(
                      name: nameController.text,
                      type: modelType,
                      url: urlController.text,
                      key: keyController.text,
                      modelName: modelNameController.text.isNotEmpty ? modelNameController.text : null,
                      protocol: modelType == 'websocket'
                          ? (protocolController.text.isNotEmpty ? protocolController.text : null)
                          : null,
                      httpAsrIntervalSec: httpAsrInterval,
                    );

                    await ConfigService.saveASRModels(updatedModels);
                    setState(() {
                      _configFuture = ConfigLoader.loadConfig();
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ASR模型配置已更新')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show dialog for adding new ASR model
  void _addASRModel(BuildContext context) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final keyController = TextEditingController();
    final modelNameController = TextEditingController();
    final protocolController = TextEditingController();
    String modelType = 'websocket';
    int httpAsrInterval = 3;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加 ASR 模型'),
              content: SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '名称'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: modelType,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(value: 'websocket', child: Text('WebSocket（百炼实时流式）')),
                          DropdownMenuItem(value: 'local_funasr', child: Text('本地 FunASR（paraformer-zh-streaming）')),
                          DropdownMenuItem(value: 'http', child: Text('HTTP API')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            modelType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (modelType == 'websocket') ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'WebSocket 服务地址',
                            hintText: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: keyController,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'fun-asr-realtime',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: protocolController,
                          decoration: const InputDecoration(
                            labelText: '协议路径（可选）',
                            hintText: '/ws',
                          ),
                        ),
                      ] else if (modelType == 'local_funasr') ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'WebSocket 服务地址',
                            hintText: 'ws://localhost:10095',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'paraformer-zh-streaming',
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'API 地址',
                            hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: keyController,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: modelNameController,
                          decoration: const InputDecoration(
                            labelText: '模型名称',
                            hintText: 'qwen-audio-turbo',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: httpAsrInterval,
                          decoration: const InputDecoration(labelText: '音频发送间隔'),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 秒')),
                            DropdownMenuItem(value: 5, child: Text('5 秒')),
                            DropdownMenuItem(value: 10, child: Text('10 秒')),
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                            DropdownMenuItem(value: 60, child: Text('1 分钟')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                httpAsrInterval = value;
                              });
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final config = await _configFuture;
                    final updatedModels = List<ASRModelConfig>.from(config.asrModels);
                    updatedModels.add(ASRModelConfig(
                      name: nameController.text,
                      type: modelType,
                      url: urlController.text,
                      key: keyController.text,
                      modelName: modelNameController.text.isNotEmpty ? modelNameController.text : null,
                      protocol: modelType == 'websocket'
                          ? (protocolController.text.isNotEmpty ? protocolController.text : null)
                          : null,
                      httpAsrIntervalSec: httpAsrInterval,
                    ));

                    await ConfigService.saveASRModels(updatedModels);
                    setState(() {
                      _configFuture = ConfigLoader.loadConfig();
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('新的ASR模型已添加')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 预设摘要模型列表
  static const List<Map<String, String>> _presetModels = [
    {'name': '阿里云 Qwen', 'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'modelName': 'qwen3.5-plus'},
    {'name': 'DeepSeek', 'url': 'https://api.deepseek.com/v1', 'modelName': 'deepseek-chat'},
    {'name': '小米 MiMo', 'url': 'https://api.xiaomi.com/v1', 'modelName': 'mimo'},
    {'name': 'Kimi (Moonshot)', 'url': 'https://api.moonshot.cn/v1', 'modelName': 'moonshot-v1-128k'},
    {'name': 'ChatGPT (OpenAI)', 'url': 'https://api.openai.com/v1', 'modelName': 'gpt-4o'},
    {'name': 'Claude (Anthropic)', 'url': 'https://api.anthropic.com/v1', 'modelName': 'claude-sonnet-4-20250514'},
  ];

  // Function to show dialog for editing Summary model
  void _editSummaryModel(BuildContext context, SummaryModelConfig model, int index) async {
    final nameController = TextEditingController(text: model.name);
    final urlController = TextEditingController(text: model.url);
    final keyController = TextEditingController(text: model.key);
    final modelNameController = TextEditingController(text: model.modelName);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('编辑摘要模型 - ${model.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '显示名称（备注用）'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '快速选择预设'),
                      items: _presetModels.map((p) {
                        return DropdownMenuItem(value: p['url'], child: Text(p['name']!));
                      }).toList(),
                      onChanged: (url) {
                        if (url != null) {
                          final preset = _presetModels.firstWhere((p) => p['url'] == url);
                          setDialogState(() {
                            urlController.text = preset['url']!;
                            modelNameController.text = preset['modelName']!;
                            if (nameController.text.isEmpty) {
                              nameController.text = preset['name']!;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelNameController,
                      decoration: const InputDecoration(
                        labelText: '模型名称',
                        hintText: '例如: qwen-plus, deepseek-chat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(labelText: 'API 地址'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final config = await _configFuture;
                    final updatedModels = List<SummaryModelConfig>.from(config.summaryModels);
                    updatedModels[index] = SummaryModelConfig(
                      name: nameController.text,
                      url: urlController.text,
                      key: keyController.text,
                      modelName: modelNameController.text.isNotEmpty ? modelNameController.text : 'qwen3.5-plus',
                    );
                    await ConfigService.saveSummaryModels(updatedModels);
                    setState(() {
                      _configFuture = ConfigLoader.loadConfig();
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('摘要模型配置已更新')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show dialog for adding new Summary model
  void _addSummaryModel(BuildContext context) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final keyController = TextEditingController();
    final modelNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加摘要模型'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '显示名称（备注用）'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '快速选择预设'),
                      items: _presetModels.map((p) {
                        return DropdownMenuItem(value: p['url'], child: Text(p['name']!));
                      }).toList(),
                      onChanged: (url) {
                        if (url != null) {
                          final preset = _presetModels.firstWhere((p) => p['url'] == url);
                          setDialogState(() {
                            urlController.text = preset['url']!;
                            modelNameController.text = preset['modelName']!;
                            if (nameController.text.isEmpty) {
                              nameController.text = preset['name']!;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelNameController,
                      decoration: const InputDecoration(
                        labelText: '模型名称',
                        hintText: '例如: qwen-plus, deepseek-chat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(labelText: 'API 地址'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final config = await _configFuture;
                    final updatedModels = List<SummaryModelConfig>.from(config.summaryModels);
                    updatedModels.add(SummaryModelConfig(
                      name: nameController.text,
                      url: urlController.text,
                      key: keyController.text,
                      modelName: modelNameController.text.isNotEmpty ? modelNameController.text : 'qwen3.5-plus',
                    ));
                    await ConfigService.saveSummaryModels(updatedModels);
                    setState(() {
                      _configFuture = ConfigLoader.loadConfig();
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('新的摘要模型已添加')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show dialog for editing S3 configuration
  void _editS3Config(BuildContext context, S3Config config) async {
    final endpointController = TextEditingController(text: config.endpoint);
    final bucketController = TextEditingController(text: config.bucket);
    final regionController = TextEditingController(text: config.region);
    final accessKeyController = TextEditingController(text: config.accessKey);
    final secretKeyController = TextEditingController(text: config.secretKey);
    bool usePathStyle = config.usePathStyle;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('编辑 S3 配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: endpointController,
                      decoration: const InputDecoration(
                        labelText: '端点地址',
                        hintText: 'https://oss-cn-hangzhou.aliyuncs.com',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bucketController,
                      decoration: const InputDecoration(labelText: '存储桶'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: regionController,
                      decoration: const InputDecoration(labelText: '区域'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: accessKeyController,
                      decoration: const InputDecoration(labelText: '访问密钥'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: secretKeyController,
                      decoration: const InputDecoration(labelText: '私密密钥'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('路径样式'),
                        const Spacer(),
                        Switch(
                          value: usePathStyle,
                          onChanged: (v) => setDialogState(() => usePathStyle = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final updatedConfig = S3Config(
                      endpoint: endpointController.text,
                      bucket: bucketController.text,
                      region: regionController.text,
                      accessKey: accessKeyController.text,
                      secretKey: secretKeyController.text,
                      usePathStyle: usePathStyle,
                    );
                    await ConfigService.saveS3Config(updatedConfig);
                    setState(() => _configFuture = ConfigLoader.loadConfig());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('S3配置已更新')),
                      );
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show dialog for editing WebDAV configuration
  void _editWebDAVConfig(BuildContext context, WebDAVConfig config) async {
    final urlController = TextEditingController(text: config.url);
    final usernameController = TextEditingController(text: config.username);
    final passwordController = TextEditingController(text: config.password);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('编辑 WebDAV 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://dav.example.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: '密码'),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final updatedConfig = WebDAVConfig(
                  url: urlController.text,
                  username: usernameController.text,
                  password: passwordController.text,
                );
                await ConfigService.saveWebDAVConfig(updatedConfig);
                setState(() => _configFuture = ConfigLoader.loadConfig());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('WebDAV配置已更新')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: FutureBuilder<AppConfig>(
        future: _configFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error loading config: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No configuration data'));
          } else {
            final config = snapshot.data!;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '用户设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('暗色主题'),
                    value: _darkMode,
                    onChanged: (value) {
                      setState(() {
                        _darkMode = value;
                      });
                      themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('启用通知'),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                      _saveSettings();
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ASR 模型',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          _addASRModel(context);
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (config.asrModels.isNotEmpty)
                    for (var i = 0; i < config.asrModels.length; i++)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: ListTile(
                          title: Text(config.asrModels[i].name),
                          subtitle: Text(config.asrModels[i].url),
                          trailing: const Icon(Icons.edit),
                          onTap: () {
                            _editASRModel(context, config.asrModels[i], i);
                          },
                        ),
                      )
                  else
                    const Text('未配置 ASR 模型'),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '摘要模型',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          _addSummaryModel(context);
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (config.summaryModels.isNotEmpty)
                    for (var i = 0; i < config.summaryModels.length; i++)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: ListTile(
                          title: Text(config.summaryModels[i].name),
                          subtitle: Text('模型: ${config.summaryModels[i].modelName}'),
                          trailing: const Icon(Icons.edit),
                          onTap: () {
                            _editSummaryModel(context, config.summaryModels[i], i);
                          },
                        ),
                      )
                  else
                    const Text('未配置摘要模型'),
                  const SizedBox(height: 20),
                  const Text(
                    '存储配置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: const Text('S3 / OSS 配置'),
                      subtitle: Text(
                        config.storage.s3.isConfigured
                            ? '${config.storage.s3.bucket} @ ${config.storage.s3.endpoint.split('//').last.split('/').first}'
                            : '未配置',
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        _editS3Config(context, config.storage.s3);
                      },
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: const Text('WebDAV 配置'),
                      subtitle: Text(
                        config.storage.webdav.isConfigured
                            ? '${config.storage.webdav.username} @ ${config.storage.webdav.url}'
                            : '未配置',
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        _editWebDAVConfig(context, config.storage.webdav);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '会议模板',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: const Icon(Icons.description),
                      title: const Text('管理会议模板'),
                      subtitle: const Text('添加、编辑或删除会议纪要模板'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TemplateManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '存储管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: FutureBuilder<int>(
                      future: StorageService().calculateStorageUsage(),
                      builder: (context, snapshot) {
                        final size = snapshot.data ?? 0;
                        final sizeStr = size > 1024 * 1024
                            ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
                            : size > 1024
                                ? '${(size / 1024).toStringAsFixed(1)} KB'
                                : '$size B';
                        return ListTile(
                          title: const Text('存储占用'),
                          subtitle: Text('当前已使用 $sizeStr'),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('存储占用: $sizeStr')),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '关于',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Card(
                    margin: EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text('言记'),
                      subtitle: Text('Version 1.0.0'),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      ),
    );
  }
}