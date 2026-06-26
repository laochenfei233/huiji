import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yanji/models/ai_model.dart';
import 'package:yanji/services/model_download_service.dart';
import 'package:yanji/services/config_service.dart';
import 'package:yanji/utils/config_loader.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  final _downloadService = ModelDownloadService();
  List<LocalModel> _localModels = [];
  bool _isLoading = true;
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await _downloadService.getLocalModels();
    setState(() {
      _localModels = models;
      _isLoading = false;
    });
  }

  Future<void> _downloadModel(AIModel model, {bool force = false}) async {
    if (_isDownloading[model.id] == true) return;

    setState(() {
      _isDownloading[model.id] = true;
      _downloadProgress[model.id] = 0;
    });

    await _downloadService.downloadModel(
      model,
      force: force,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress[model.id] = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDownloading[model.id] = false;
        _downloadProgress.remove(model.id);
      });
      await _loadModels();
    }
  }

  Future<void> _deleteModel(String modelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个模型吗？删除后需要重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadService.deleteModel(modelId);
      await _loadModels();
    }
  }

  Future<void> _selectModel(LocalModel localModel) async {
    final config = ASRModelConfig(
      name: localModel.model.name,
      type: 'local_funasr_onnx',
      url: '',
      modelPath: localModel.localPath,
      modelName: localModel.model.id,
    );

    final existingModels = await ConfigService.loadASRModels();

    final index = existingModels.indexWhere(
      (m) => m.type == 'local_funasr_onnx' && m.modelName == localModel.model.id,
    );

    if (index >= 0) {
      existingModels[index] = config;
    } else {
      existingModels.add(config);
    }

    await ConfigService.saveASRModels(existingModels);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择 ${localModel.model.name}')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型管理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadModels,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSection('已下载模型', _localModels.where((m) => m.isDownloaded).toList()),
                  const SizedBox(height: 16),
                  _buildSection('可用模型', _localModels.where((m) => !m.isDownloaded).toList()),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<LocalModel> models) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (models.isEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 20, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('暂无模型', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...models.map(_buildModelCard),
      ],
    );
  }

  Widget _buildModelCard(LocalModel localModel) {
    final model = localModel.model;
    final isDownloading = _isDownloading[model.id] == true;
    final progress = _downloadProgress[model.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  model.type == 'asr' ? Icons.mic : Icons.extension,
                  size: 20,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(model.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Text(model.totalSizeStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
            ],
            if (!isDownloading && localModel.isDownloaded) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _deleteModel(model.id),
                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _downloadModel(model, force: true),
                    child: const Text('重新下载'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _selectModel(localModel),
                    child: const Text('选择使用'),
                  ),
                ],
              ),
            ],
            if (!isDownloading && !localModel.isDownloaded) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => _downloadModel(model),
                    child: const Text('下载'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
