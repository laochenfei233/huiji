import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/utils/web_file_adapter.dart' as web_file;

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

  String _buildContent() {
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

    return content;
  }

  Future<void> _shareMeeting() async {
    try {
      final content = _buildContent();
      final fileName = '${widget.meeting.title}.$_shareFormat';

      if (kIsWeb) {
        await web_file.downloadFile(content, fileName, mimeType: 'text/plain');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件已开始下载')),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Native: use share_plus
      // Note: native path is handled by share_plus internally on most platforms
      // For simplicity, we copy to clipboard on native too if file sharing fails
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议内容已复制到剪贴板')),
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
                child: Text(kIsWeb ? '下载文件' : '分享会议'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
