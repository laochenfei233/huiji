import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/utils/web_file_adapter.dart' as web_file;

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final StorageService _storageService = StorageService();
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入会议')),
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
              '支持格式',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('• TXT 文本文件 — 作为会议转录导入'),
            const Text('• JSON 文件 — 完整会议数据导入'),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndImportFile() async {
    try {
      final content = await web_file.pickFile(
        acceptedExtensions: ['.txt', '.json'],
      );

      if (content == null) {
        setState(() => _status = '未选择文件');
        return;
      }

      setState(() => _status = '正在导入...');

      // Parse and save
      Meeting meeting;
      if (content.trimLeft().startsWith('{')) {
        // JSON format
        final map = Map<String, dynamic>.from(
          jsonDecode(content.trim()),
        );
        // Try to parse as meeting
        try {
          meeting = Meeting.fromMap(map);
        } catch (_) {
          meeting = Meeting(
            title: '导入的会议',
            date: DateTime.now(),
            transcript: content,
            summary: '',
            folderName: '',
          );
        }
      } else {
        // TXT format
        meeting = Meeting(
          title: '导入的会议 ${DateTime.now().month}-${DateTime.now().day}',
          date: DateTime.now(),
          transcript: content,
          summary: '',
          folderName: '',
        );
      }

      await _storageService.saveMeeting(meeting);

      if (mounted) {
        setState(() => _status = '导入成功: ${meeting.title}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('会议「${meeting.title}」已导入')),
        );
      }
    } catch (e) {
      setState(() => _status = '导入失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }
}
