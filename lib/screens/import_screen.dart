import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final StorageService _storageService = StorageService();
  List<FileSystemEntity> _files = [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final directory = await _storageService.getDocumentsDirectory();
      final files = directory.listSync();
      setState(() {
        _files = files.where((file) => file is File).toList();
      });
    } catch (e) {
      setState(() {
        _status = '加载文件失败: $e';
      });
    }
  }

  Future<void> _pickAndImportFile() async {
    try {
      // Simplified file picking for demo purposes
      setState(() {
        _status = '文件导入功能暂未实现';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件导入功能暂未实现')),
        );
      }
    } catch (e) {
      setState(() {
        _status = '导入失败: $e';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入会议'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: _pickAndImportFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('选择文件导入'),
            ),
            const SizedBox(height: 20),
            Text(_status),
            const SizedBox(height: 20),
            const Text(
              '最近导入的文件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _files.isEmpty
                  ? const Center(child: Text('未找到文件'))
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index] as File;
                        return ListTile(
                          title: Text(file.path.split('/').last),
                          subtitle: Text('${(file.lengthSync() / 1024).toStringAsFixed(2)} KB'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
