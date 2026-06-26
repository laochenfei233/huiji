import 'package:flutter/material.dart';
import 'package:yanji/main.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/services/config_service.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/screens/template_management_screen.dart';
import 'package:yanji/screens/model_management_screen.dart';
import 'package:yanji/screens/llm_model_management_screen.dart';
import 'package:yanji/widgets/model_edit_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<AppConfig> _configFuture;
  bool _darkMode = false;
  bool _notificationsEnabled = true;
  bool _recordingNotification = true;
  bool _lockScreenRecording = true;

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
      _recordingNotification = prefs.getBool('recording_notification') ?? true;
      _lockScreenRecording = prefs.getBool('lock_screen_recording') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _darkMode);
    await prefs.setBool('notifications_enabled', _notificationsEnabled);
    await prefs.setBool('recording_notification', _recordingNotification);
    await prefs.setBool('lock_screen_recording', _lockScreenRecording);
  }

  void _refreshConfig() {
    setState(() => _configFuture = ConfigLoader.loadConfig());
  }

  void _editASRModel(BuildContext context, ASRModelConfig model, int index) {
    showASRModelDialog(
      context: context,
      existingModel: model,
      index: index,
      configFuture: _configFuture,
      onSaved: _refreshConfig,
    );
  }

  void _addASRModel(BuildContext context) {
    showASRModelDialog(
      context: context,
      existingModel: null,
      index: null,
      configFuture: _configFuture,
      onSaved: _refreshConfig,
    );
  }

  // 长按删除确认
  Future<bool> _confirmDelete(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「$name」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _editSummaryModel(BuildContext context, SummaryModelConfig model, int index) {
    showSummaryModelDialog(
      context: context,
      existingModel: model,
      index: index,
      configFuture: _configFuture,
      onSaved: _refreshConfig,
    );
  }

  void _addSummaryModel(BuildContext context) {
    showSummaryModelDialog(
      context: context,
      existingModel: null,
      index: null,
      configFuture: _configFuture,
      onSaved: _refreshConfig,
    );
  }

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
                  SwitchListTile(
                    title: const Text('录音通知'),
                    subtitle: const Text('录音时在通知栏显示状态'),
                    value: _recordingNotification,
                    onChanged: (value) {
                      setState(() {
                        _recordingNotification = value;
                      });
                      _saveSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('锁屏录音'),
                    subtitle: const Text('锁屏后继续录音，保持屏幕唤醒'),
                    value: _lockScreenRecording,
                    onChanged: (value) {
                      setState(() {
                        _lockScreenRecording = value;
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
                          onLongPress: () async {
                            if (await _confirmDelete(config.asrModels[i].name)) {
                              final updated = List<ASRModelConfig>.from(config.asrModels)..removeAt(i);
                              await ConfigService.saveASRModels(updated);
                              setState(() => _configFuture = ConfigLoader.loadConfig());
                            }
                          },
                        ),
                      )
                  else
                    const Text('未配置 ASR 模型'),
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: const Icon(Icons.download),
                      title: const Text('模型管理'),
                      subtitle: const Text('下载和管理本地 ASR 模型'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ModelManagementScreen(),
                          ),
                        );
                        setState(() {
                          _configFuture = ConfigLoader.loadConfig();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LLM 模型',
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
                          onLongPress: () async {
                            if (await _confirmDelete(config.summaryModels[i].name)) {
                              final updated = List<SummaryModelConfig>.from(config.summaryModels)..removeAt(i);
                              await ConfigService.saveSummaryModels(updated);
                              setState(() => _configFuture = ConfigLoader.loadConfig());
                            }
                          },
                        ),
                      )
                  else
                    const Text('未配置 LLM 模型'),
                  const SizedBox(height: 10),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: const Icon(Icons.download),
                      title: const Text('本地 LLM 模型管理'),
                      subtitle: const Text('下载和管理本地 LLM 模型（离线摘要）'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LlmModelManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ),
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
                      onLongPress: () async {
                        if (await _confirmDelete('S3 / OSS 配置')) {
                          await ConfigService.saveS3Config(S3Config());
                          setState(() => _configFuture = ConfigLoader.loadConfig());
                        }
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
                      onLongPress: () async {
                        if (await _confirmDelete('WebDAV 配置')) {
                          await ConfigService.saveWebDAVConfig(WebDAVConfig());
                          setState(() => _configFuture = ConfigLoader.loadConfig());
                        }
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