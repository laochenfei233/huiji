import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareMeetingScreen extends StatefulWidget {
  final Meeting meeting;
  
  const ShareMeetingScreen({super.key, required this.meeting});

  @override
  State<ShareMeetingScreen> createState() => _ShareMeetingScreenState();
}

class _ShareMeetingScreenState extends State<ShareMeetingScreen> {
  final StorageService _storageService = StorageService();
  bool _shareTranscript = true;
  bool _shareSummary = true;
  bool _shareWithParticipants = true;
  String _shareFormat = 'txt';
  String _transcript = '';
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.meeting.id == null) return;
    final detail = await _storageService.loadMeetingDetail(widget.meeting.id!);
    if (detail != null && mounted) {
      setState(() {
        _transcript = detail.transcript;
        _summary = detail.summary;
      });
    }
  }

  Future<void> _shareMeeting() async {
    try {
      String content = '会议标题: ${widget.meeting.title}\n';
      content += '会议时间: ${widget.meeting.date}\n\n';

      if (_shareWithParticipants && widget.meeting.participants.isNotEmpty) {
        content += '参与者:\n';
        for (var participant in widget.meeting.participants) {
          content += '- ${participant.name}\n';
        }
        content += '\n';
      }

      if (_shareTranscript && _transcript.isNotEmpty) {
        content += '会议转录:\n$_transcript\n\n';
      }

      if (_shareSummary && _summary.isNotEmpty) {
        content += '会议摘要:\n$_summary\n\n';
      }
      
      // Save content to a temporary file
      final directory = await getTemporaryDirectory();
      final fileName = '${widget.meeting.title}.${_shareFormat}';
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      
      if (_shareFormat == 'txt') {
        await file.writeAsString(content);
      } else {
        // For other formats, we would need additional packages
        await file.writeAsString(content);
      }
      
      // Share the file
      await Share.shareXFiles([XFile(filePath)], text: '分享会议记录: ${widget.meeting.title}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议已分享')),
        );
        
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分享会议'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '会议标题',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(widget.meeting.title),
            const SizedBox(height: 20),
            const Text(
              '分享格式',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('TXT 文本文件'),
              trailing: Radio<String>(
                value: 'txt',
                groupValue: _shareFormat,
                onChanged: (value) {
                  setState(() {
                    _shareFormat = value!;
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('JSON 文件'),
              trailing: Radio<String>(
                value: 'json',
                groupValue: _shareFormat,
                onChanged: (value) {
                  setState(() {
                    _shareFormat = value!;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '分享内容',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('转录内容'),
              value: _shareTranscript,
              onChanged: (value) {
                setState(() {
                  _shareTranscript = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('会议摘要'),
              value: _shareSummary,
              onChanged: (value) {
                setState(() {
                  _shareSummary = value;
                });
              },
            ),
            SwitchListTile(
              title: const Text('参与者信息'),
              value: _shareWithParticipants,
              onChanged: (value) {
                setState(() {
                  _shareWithParticipants = value;
                });
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _shareMeeting,
                child: const Text('分享会议'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}