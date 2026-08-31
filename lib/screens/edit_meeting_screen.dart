import 'package:flutter/material.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';

class EditMeetingScreen extends StatefulWidget {
  final Meeting meeting;
  
  const EditMeetingScreen({super.key, required this.meeting});

  @override
  State<EditMeetingScreen> createState() => _EditMeetingScreenState();
}

class _EditMeetingScreenState extends State<EditMeetingScreen> {
  final StorageService _storageService = StorageService();
  late TextEditingController _titleController;
  late TextEditingController _transcriptController;
  late TextEditingController _summaryController;
  late Meeting _meeting;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    _titleController = TextEditingController(text: _meeting.title);
    _transcriptController = TextEditingController(text: _meeting.transcript ?? '');
    _summaryController = TextEditingController(text: _meeting.summary ?? '');
    _wordCount = (_meeting.transcript ?? '').split(RegExp(r'\s+')).length;
    
    // Listen for changes in transcript to update word count
    _transcriptController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _transcriptController.removeListener(_updateWordCount);
    _transcriptController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    setState(() {
      _wordCount = _transcriptController.text.split(RegExp(r'\s+')).length;
    });
  }

  Future<void> _saveChanges() async {
    try {
      final updatedMeeting = Meeting(
        id: _meeting.id,
        title: _titleController.text,
        date: _meeting.date,
        transcript: _transcriptController.text,
        summary: _summaryController.text,
        participants: _meeting.participants,
        recordingDuration: _meeting.recordingDuration,
        folderName: _meeting.folderName,
      );
      
      await _storageService.updateMeeting(updatedMeeting);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议记录已更新')),
        );
        
        // Return the updated meeting
        Navigator.pop(context, updatedMeeting);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteMeeting() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个会议记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirm == true && mounted) {
      try {
        if (_meeting.id != null) {
          await _storageService.deleteMeeting(_meeting.id!);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('会议记录已删除')),
            );
            Navigator.pop(context); // Close edit screen
            Navigator.pop(context); // Close detail screen
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑会议记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveChanges,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '会议标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('字数统计: $_wordCount'),
            const SizedBox(height: 16),
            const Text(
              '转录内容:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: TextField(
                  controller: _transcriptController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8.0),
                  ),
                  maxLines: null,
                  expands: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '会议摘要:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: TextField(
                  controller: _summaryController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8.0),
                  ),
                  maxLines: null,
                  expands: false,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: _deleteMeeting,
                icon: const Icon(Icons.delete),
                label: const Text('删除会议记录'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white, backgroundColor: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}