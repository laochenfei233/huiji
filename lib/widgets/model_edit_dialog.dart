import 'package:flutter/material.dart';
import 'package:yanji/utils/config_loader.dart';
import 'package:yanji/services/config_service.dart';

/// ASR 模型编辑/添加对话框
Future<void> showASRModelDialog({
  required BuildContext context,
  required ASRModelConfig? existingModel,
  required int? index,
  required Future<AppConfig> configFuture,
  required VoidCallback onSaved,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: existingModel?.name ?? '');
  final urlController = TextEditingController(text: existingModel?.url ?? '');
  final keyController = TextEditingController(text: existingModel?.key ?? '');
  final modelNameController = TextEditingController(text: existingModel?.modelName ?? '');
  final protocolController = TextEditingController(text: existingModel?.protocol ?? '');
  String modelType = existingModel?.type ?? 'http';
  int httpAsrInterval = existingModel?.httpAsrIntervalSec ?? 3;

  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existingModel != null ? '编辑 ASR 模型 - ${existingModel.name}' : '添加 ASR 模型'),
            content: SizedBox(
              width: double.infinity,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '名称 *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: modelType,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(value: 'websocket', child: Text('websocket')),
                          DropdownMenuItem(value: 'local_funasr', child: Text('本地')),
                          DropdownMenuItem(value: 'local_funasr_onnx', child: Text('本地ONNX')),
                          DropdownMenuItem(value: 'http', child: Text('httpAPI')),
                        ],
                        onChanged: (value) {
                          setDialogState(() => modelType = value!);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (modelType == 'websocket') ...[
                        TextFormField(
                          controller: urlController,
                          decoration: const InputDecoration(labelText: '地址 *', hintText: 'wss://...'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入地址' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: keyController,
                          decoration: const InputDecoration(labelText: 'Key', hintText: 'sk-...'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: modelNameController,
                          decoration: const InputDecoration(labelText: '模型', hintText: 'fun-asr-realtime'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: protocolController,
                          decoration: const InputDecoration(labelText: '路径', hintText: '/ws'),
                        ),
                      ] else if (modelType == 'local_funasr') ...[
                        TextFormField(
                          controller: urlController,
                          decoration: const InputDecoration(labelText: '地址 *', hintText: 'ws://localhost:10095'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入地址' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: modelNameController,
                          decoration: const InputDecoration(labelText: '模型', hintText: 'paraformer-zh-streaming'),
                        ),
                      ] else if (modelType == 'local_funasr_onnx') ...[
                        TextFormField(
                          controller: modelNameController,
                          decoration: const InputDecoration(labelText: '模型', hintText: 'sherpa_paraformer_offline'),
                          enabled: false,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '模型文件由"模型管理"自动配置',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ] else ...[
                        TextFormField(
                          controller: urlController,
                          decoration: const InputDecoration(labelText: '地址 *', hintText: 'https://...'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入地址' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: keyController,
                          decoration: const InputDecoration(labelText: 'Key', hintText: 'sk-...'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: modelNameController,
                          decoration: const InputDecoration(labelText: '模型', hintText: 'qwen-audio-turbo'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: httpAsrInterval,
                          decoration: const InputDecoration(labelText: '间隔'),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 秒')),
                            DropdownMenuItem(value: 5, child: Text('5 秒')),
                            DropdownMenuItem(value: 10, child: Text('10 秒')),
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                            DropdownMenuItem(value: 60, child: Text('1 分钟')),
                          ],
                          onChanged: (value) {
                            if (value != null) setDialogState(() => httpAsrInterval = value);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(context).pop(true);
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

  if (result != true) return;

  final config = await configFuture;
  final updatedModels = List<ASRModelConfig>.from(config.asrModels);
  final newModel = ASRModelConfig(
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

  if (index != null) {
    updatedModels[index] = newModel;
  } else {
    updatedModels.add(newModel);
  }

  await ConfigService.saveASRModels(updatedModels);
  onSaved();
}

/// LLM 模型编辑/添加对话框
Future<void> showSummaryModelDialog({
  required BuildContext context,
  required SummaryModelConfig? existingModel,
  required int? index,
  required Future<AppConfig> configFuture,
  required VoidCallback onSaved,
}) async {
  const presetModels = [
    {'name': '阿里云 Qwen', 'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'modelName': 'qwen3.5-plus'},
    {'name': 'DeepSeek', 'url': 'https://api.deepseek.com/v1', 'modelName': 'deepseek-chat'},
    {'name': '小米 MiMo', 'url': 'https://api.xiaomi.com/v1', 'modelName': 'mimo'},
    {'name': 'Kimi (Moonshot)', 'url': 'https://api.moonshot.cn/v1', 'modelName': 'moonshot-v1-128k'},
    {'name': 'ChatGPT (OpenAI)', 'url': 'https://api.openai.com/v1', 'modelName': 'gpt-4o'},
    {'name': 'Claude (Anthropic)', 'url': 'https://api.anthropic.com/v1', 'modelName': 'claude-sonnet-4-20250514'},
  ];

  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: existingModel?.name ?? '');
  final urlController = TextEditingController(text: existingModel?.url ?? '');
  final keyController = TextEditingController(text: existingModel?.key ?? '');
  final modelNameController = TextEditingController(text: existingModel?.modelName ?? '');

  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existingModel != null ? '编辑 LLM 模型 - ${existingModel.name}' : '添加 LLM 模型'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '显示名称 *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '快速选择预设'),
                      items: presetModels.map((p) {
                        return DropdownMenuItem(value: p['url'], child: Text(p['name']!));
                      }).toList(),
                      onChanged: (url) {
                        if (url != null) {
                          final preset = presetModels.firstWhere((p) => p['url'] == url);
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
                    TextFormField(
                      controller: modelNameController,
                      decoration: const InputDecoration(
                        labelText: '模型名称 *',
                        hintText: '例如: qwen-plus, deepseek-chat',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入模型名称' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      decoration: const InputDecoration(labelText: 'API 地址 *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入 API 地址' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key *',
                        hintText: 'sk-...',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(context).pop(true);
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

  if (result != true) return;

  final config = await configFuture;
  final updatedModels = List<SummaryModelConfig>.from(config.summaryModels);
  final newModel = SummaryModelConfig(
    name: nameController.text,
    url: urlController.text,
    key: keyController.text,
    modelName: modelNameController.text.isNotEmpty ? modelNameController.text : 'qwen3.5-plus',
  );

  if (index != null) {
    updatedModels[index] = newModel;
  } else {
    updatedModels.add(newModel);
  }

  await ConfigService.saveSummaryModels(updatedModels);
  onSaved();
}
