import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:yanji/models/ai_model.dart';

class DownloadState {
  final String modelId;
  final bool isComplete;

  DownloadState({required this.modelId, this.isComplete = false});

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'isComplete': isComplete,
      };

  factory DownloadState.fromJson(Map<String, dynamic> json) => DownloadState(
        modelId: json['modelId'] as String,
        isComplete: json['isComplete'] as bool? ?? false,
      );
}

class ModelDownloadService {
  static const _modelsDir = 'models';

  Future<Directory> _getModelsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_modelsDir');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getModelDir(String modelId) async {
    final modelsDir = await _getModelsDir();
    final dir = Directory('${modelsDir.path}/$modelId');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<DownloadState> _loadDownloadState(String modelId) async {
    final dir = await _getModelDir(modelId);
    final stateFile = File('${dir.path}/.download_state.json');
    if (stateFile.existsSync()) {
      final json = jsonDecode(await stateFile.readAsString());
      return DownloadState.fromJson(json);
    }
    return DownloadState(modelId: modelId);
  }

  Future<void> _saveDownloadState(DownloadState state) async {
    final dir = await _getModelDir(state.modelId);
    final stateFile = File('${dir.path}/.download_state.json');
    await stateFile.writeAsString(jsonEncode(state.toJson()));
  }

  Future<List<LocalModel>> getLocalModels() async {
    final modelsDir = await _getModelsDir();
    final List<LocalModel> localModels = [];

    for (final model in kAvailableModels) {
      final dir = Directory('${modelsDir.path}/${model.id}');
      final state = await _loadDownloadState(model.id);
      bool isDownloaded = state.isComplete && dir.existsSync();
      if (isDownloaded) {
        for (final file in [...model.files, ...model.companionFiles]) {
          final f = File('${dir.path}/${file.filename}');
          if (!f.existsSync() || (file.sizeBytes > 0 && f.lengthSync() != file.sizeBytes)) {
            isDownloaded = false;
            debugPrint('[ModelDownload] 文件校验失败: ${file.filename}');
            await _saveDownloadState(DownloadState(modelId: model.id, isComplete: false));
            break;
          }
        }
      }

      localModels.add(LocalModel(
        model: model,
        localPath: dir.path,
        isDownloaded: isDownloaded,
      ));
    }

    return localModels;
  }

  Future<String?> getModelPath(String modelId) async {
    final state = await _loadDownloadState(modelId);
    if (!state.isComplete) return null;
    final dir = await _getModelDir(modelId);
    return dir.path;
  }

  Future<void> downloadModel(
    AIModel model, {
    bool force = false,
    Function(double progress, String status)? onProgress,
  }) async {
    final dir = await _getModelDir(model.id);
    final state = await _loadDownloadState(model.id);

    if (state.isComplete && !force) {
      final allFiles = [...model.files, ...model.companionFiles];
      bool allValid = true;
      for (final file in allFiles) {
        final f = File('${dir.path}/${file.filename}');
        if (!f.existsSync() || (f.lengthSync() != file.sizeBytes && file.sizeBytes > 0)) {
          allValid = false;
          debugPrint('[ModelDownload] 文件校验失败: ${file.filename} '
              '期望=${file.sizeBytes} 实际=${f.existsSync() ? f.lengthSync() : "不存在"}');
          break;
        }
      }
      if (allValid) {
        debugPrint('[ModelDownload] ${model.name} 已存在且完整，跳过');
        return;
      }
      debugPrint('[ModelDownload] ${model.name} 文件不完整，重新下载');
      final incompleteState = DownloadState(modelId: model.id, isComplete: false);
      await _saveDownloadState(incompleteState);
    }

    try {
      final allFiles = [...model.files, ...model.companionFiles];
      final pendingFiles = <ModelFileItem>[];
      for (final file in allFiles) {
        final savePath = '${dir.path}/${file.filename}';
        final f = File(savePath);
        if (f.existsSync() && (f.lengthSync() == file.sizeBytes || file.sizeBytes <= 0)) {
          continue;
        }
        if (f.existsSync()) {
          await f.delete();
          debugPrint('[ModelDownload] 删除不完整文件: ${file.filename}');
        }
        pendingFiles.add(file);
      }

      if (pendingFiles.isEmpty) {
        final completedState = DownloadState(modelId: model.id, isComplete: true);
        await _saveDownloadState(completedState);
        onProgress?.call(1.0, '完成');
        return;
      }

      // 计算总字节数和已下载字节数（用于真实进度）
      final totalBytes = allFiles.fold<int>(0, (sum, f) => sum + (f.sizeBytes > 0 ? f.sizeBytes : 0));
      int downloadedBytes = allFiles.where((f) => pendingFiles.every((p) => p.filename != f.filename))
          .fold<int>(0, (sum, f) => sum + f.sizeBytes); // 已存在文件的字节数

      debugPrint('[ModelDownload] ${model.name}: 需下载 ${pendingFiles.length} 个文件，总计 ${totalBytes ~/ 1024 ~/ 1024} MB');

      // 使用锁实现并发下载
      int nextIndex = 0;
      final completer = Completer<void>();
      String? lastError;
      int activeCount = 0;
      final lock = Completer<void>();
      lock.complete(); // 初始已完成

      void updateProgress(int bytesDownloaded, String fileName) {
        downloadedBytes += bytesDownloaded;
        if (totalBytes > 0) {
          final progress = downloadedBytes / totalBytes;
          final downloadedMB = downloadedBytes / 1024 / 1024;
          final totalMB = totalBytes / 1024 / 1024;
          // 流式传输阶段最多显示99%，100%仅在真正完成后显示
          onProgress?.call(progress.clamp(0.0, 0.99), '${downloadedMB.toStringAsFixed(1)} MB / ${totalMB.toStringAsFixed(1)} MB');
        } else {
          onProgress?.call(0.5, '下载中...');
        }
      }

      Future<void> downloadNext() async {
        while (nextIndex < pendingFiles.length) {
          final file = pendingFiles[nextIndex++];
          final savePath = '${dir.path}/${file.filename}';
          final displayName = file.filename.split('/').last;

          try {
            debugPrint('[ModelDownload] 下载: ${file.filename}');
            await _downloadFile(file.filename, savePath, repo: model.repo,
                onProgress: (bytes) => updateProgress(bytes, displayName));
            final downloadedFile = File(savePath);
            if (file.sizeBytes > 0 && downloadedFile.lengthSync() != file.sizeBytes) {
              final actual = downloadedFile.lengthSync();
              await downloadedFile.delete();
              throw Exception('文件大小不匹配: 期望 ${file.sizeBytes} 字节, 实际 $actual 字节');
            }
          } catch (e) {
            lastError = '下载失败: ${file.filename} - $e';
            debugPrint('[ModelDownload] $lastError');
            final partialFile = File(savePath);
            if (partialFile.existsSync()) {
              await partialFile.delete();
            }
          }

          activeCount--;
          if (nextIndex < pendingFiles.length && !completer.isCompleted) {
            activeCount++;
            downloadNext();
          } else if (activeCount == 0 && !completer.isCompleted) {
            completer.complete();
          }
        }
      }

      const concurrency = 4; // 增加并发加速下载
      final startCount = concurrency < pendingFiles.length ? concurrency : pendingFiles.length;
      activeCount = startCount;
      for (int i = 0; i < startCount; i++) {
        downloadNext();
      }

      await completer.future;

      if (lastError != null) {
        throw Exception(lastError);
      }

      // 所有文件下载完成，校验并保存状态
      debugPrint('[ModelDownload] ${model.name}: 所有文件下载完成，开始校验...');
      for (final file in allFiles) {
        final f = File('${dir.path}/${file.filename}');
        final actualSize = f.existsSync() ? f.lengthSync() : 0;
        debugPrint('[ModelDownload]   ${file.filename}: 期望=${file.sizeBytes} 实际=$actualSize');
      }

      final completedState = DownloadState(modelId: model.id, isComplete: true);
      await _saveDownloadState(completedState);
      onProgress?.call(1.0, '完成');
      debugPrint('[ModelDownload] ${model.name} 安装完成');
    } catch (e) {
      debugPrint('[ModelDownload] 下载出错: $e');
      rethrow;
    }
  }

  /// 从 ModelScope 下载单个文件（流式下载，支持断点续传）
  Future<void> _downloadFile(String remotePath, String localPath, {String? repo, Function(int bytes)? onProgress}) async {
    final parentDir = Directory(localPath).parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    final url = 'https://modelscope.cn/api/v1/models/${repo ?? kModelScopeRepo}/repo?Revision=master&FilePath=$remotePath';
    debugPrint('[ModelDownload] URL: $url');

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final client = http.Client();
      try {
        String downloadUrl = url;
        int resumeFrom = 0;

        // 检查是否有未完成的下载（断点续传）
        final existingFile = File(localPath);
        if (existingFile.existsSync()) {
          resumeFrom = existingFile.lengthSync();
          debugPrint('[ModelDownload] 断点续传: 已下载 $resumeFrom bytes');
        }

        for (int redirectCount = 0; redirectCount < 5; redirectCount++) {
          final request = http.Request('GET', Uri.parse(downloadUrl));
          request.headers['User-Agent'] = 'Mozilla/5.0';
          if (resumeFrom > 0) {
            request.headers['Range'] = 'bytes=$resumeFrom-';
          }
          final response = await client.send(request).timeout(const Duration(seconds: 600));

          if (response.statusCode == 302 || response.statusCode == 301) {
            final redirectUrl = response.headers['location'];
            await response.stream.drain<void>();
            if (redirectUrl != null) {
              downloadUrl = redirectUrl;
              debugPrint('[ModelDownload] 重定向到 CDN');
              continue;
            }
          }

          if (response.statusCode == 200 || response.statusCode == 206) {
            final file = File(localPath);
            final sink = file.openWrite(mode: resumeFrom > 0 ? FileMode.append : FileMode.write);
            int totalBytes = resumeFrom;
            await for (final chunk in response.stream.timeout(const Duration(seconds: 120))) {
              sink.add(chunk);
              totalBytes += chunk.length;
              onProgress?.call(chunk.length);
            }
            await sink.close();
            debugPrint('[ModelDownload] 完成: $remotePath ($totalBytes bytes)');
            return;
          } else if (response.statusCode == 416) {
            // Range not satisfiable — file already complete
            debugPrint('[ModelDownload] 文件已完整: $remotePath');
            return;
          } else {
            throw Exception('下载失败: $remotePath HTTP ${response.statusCode}');
          }
        }
        throw Exception('重定向次数过多: $remotePath');
      } catch (e) {
        debugPrint('[ModelDownload] 下载失败 (第 $attempt 次): $remotePath - $e');
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 3));
      } finally {
        client.close();
      }
    }
  }

  Future<void> deleteModel(String modelId) async {
    final dir = await _getModelDir(modelId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      debugPrint('[ModelDownload] 已删除模型: $modelId');
    }
  }

  Future<int> getStorageUsage() async {
    final modelsDir = await _getModelsDir();
    if (!modelsDir.existsSync()) return 0;

    int totalSize = 0;
    await for (final entity in modelsDir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }
}
