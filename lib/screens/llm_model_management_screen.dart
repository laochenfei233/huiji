import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:yanji/models/ai_model.dart';
import 'package:yanji/services/llm_model_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LlmModelManagementScreen extends StatefulWidget {
  const LlmModelManagementScreen({super.key});

  @override
  State<LlmModelManagementScreen> createState() => _LlmModelManagementScreenState();
}

class _LlmModelManagementScreenState extends State<LlmModelManagementScreen> {
  final _downloadService = LlmModelDownloadService();
  List<LocalModel> _models = [];
  bool _isLoading = true;
  String? _currentModelId;
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};

  String get _currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadCurrentModel();
  }

  Future<void> _loadModels() async {
    final models = await _downloadService.getLocalModels();
    setState(() {
      _models = models;
      _isLoading = false;
    });
  }

  Future<void> _loadCurrentModel() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _currentModelId = prefs.getString('local_llm_model_id'));
  }

  Future<void> _setCurrentModel(LocalModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_llm_model_id', model.model.id);
    await prefs.setString('local_llm_model_path', model.localPath);
    setState(() => _currentModelId = model.model.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 ${model.model.name}')),
      );
    }
  }

  Future<void> _downloadModel(LocalModel model, {bool force = false}) async {
    if (_isDownloading[model.model.id] == true) return;

    setState(() {
      _isDownloading[model.model.id] = true;
      _downloadProgress[model.model.id] = 0;
    });

    try {
      await _downloadService.downloadModel(
        model.model,
        force: force,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _downloadProgress[model.model.id] = progress;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isDownloading[model.model.id] = false;
        _downloadProgress.remove(model.model.id);
      });
      await _loadModels();
    }
  }

  Future<void> _deleteModel(LocalModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${model.model.name}」吗？\n删除后需要重新下载。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _downloadService.deleteModel(model.model.id);
      if (_currentModelId == model.model.id) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('local_llm_model_id');
        await prefs.remove('local_llm_model_path');
        setState(() => _currentModelId = null);
      }
      await _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.model.name} 已删除')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地 LLM 模型管理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadModels();
                await _loadCurrentModel();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSection('已下载模型', _models.where((m) => m.isDownloaded).toList()),
                  const SizedBox(height: 16),
                  _buildSection('可用模型', _models.where((m) => !m.isDownloaded).toList()),
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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无模型', style: TextStyle(color: Colors.grey)),
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
    final isSelected = _currentModelId == model.id;
    final platformSupported = model.isPlatformSupported(_currentPlatform);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('当前使用', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ],
                          if (!platformSupported) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('仅电脑端', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
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
                    onPressed: () => _deleteModel(localModel),
                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _downloadModel(localModel, force: true),
                    child: const Text('重新下载'),
                  ),
                  const SizedBox(width: 8),
                  if (!isSelected && platformSupported)
                    ElevatedButton(
                      onPressed: () => _setCurrentModel(localModel),
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
                  if (platformSupported)
                    ElevatedButton(
                      onPressed: () => _downloadModel(localModel),
                      child: const Text('下载'),
                    )
                  else
                    const Text('仅限电脑端使用', style: TextStyle(color: Colors.orange, fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
