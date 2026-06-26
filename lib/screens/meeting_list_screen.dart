import 'package:flutter/material.dart';
import 'package:yanji/screens/edit_meeting_screen.dart';
import 'package:yanji/screens/meeting_detail_screen.dart';
import 'package:yanji/models/meeting.dart';
import 'package:yanji/services/storage_service.dart';

class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({super.key});

  @override
  State<MeetingListScreen> createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();
  List<Meeting>? _filteredMeetings;
  List<Meeting> _allMeetings = [];
  bool _isSearching = false;
  String? _databaseError;
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterMeetings);
    _loadMeetings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasLoaded) {
      _loadMeetings();
    }
    _hasLoaded = true;
  }

  Future<void> _loadMeetings() async {
    try {
      final meetings = await _storageService.loadMeetings();
      if (mounted) {
        setState(() {
          _allMeetings = meetings;
          _isLoading = false;
          _databaseError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _databaseError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterMeetings);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _filterMeetings() async {
    final query = _searchController.text;
    setState(() {
      _isSearching = query.isNotEmpty;
    });

    if (_isSearching) {
      try {
        final meetings = await _storageService.searchMeetings(query);
        setState(() {
          _filteredMeetings = meetings;
          _databaseError = null;
        });
      } catch (e) {
        setState(() {
          _databaseError = e.toString();
        });
      }
    }
  }

  void _showMeetingContextMenu(Meeting meeting) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                _editMeeting(meeting);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMeeting(meeting);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editMeeting(Meeting meeting) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditMeetingScreen(meeting: meeting),
      ),
    );
    if (result != null) {
      _loadMeetings();
    }
  }

  void _deleteMeeting(Meeting meeting) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除会议"${meeting.title}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _storageService.deleteMeeting(meeting.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('会议已删除')),
          );
          _loadMeetings();
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
    final meetings = _isSearching ? (_filteredMeetings ?? []) : _allMeetings;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索会议...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _isSearching = false;
                            _filteredMeetings = null;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _databaseError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text('数据库错误', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(_databaseError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    : meetings.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('暂无会议记录', style: TextStyle(fontSize: 18, color: Colors.grey)),
                                SizedBox(height: 8),
                                Text('点击右下角按钮开始新会议', style: TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            itemCount: meetings.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final meeting = meetings[index];
                              return GestureDetector(
                                onSecondaryTapUp: (details) => _showMeetingContextMenu(meeting),
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16.0),
                                    title: Text(
                                      meeting.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          '${meeting.date.year}-${meeting.date.month.toString().padLeft(2, '0')}-${meeting.date.day.toString().padLeft(2, '0')} ${meeting.date.hour.toString().padLeft(2, '0')}:${meeting.date.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        if (meeting.summary != null && meeting.summary!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            meeting.summary!.replaceAll(RegExp(r'[#*\n\r]'), '').trim().length > 10
                                                ? '${meeting.summary!.replaceAll(RegExp(r'[#*\n\r]'), '').trim().substring(0, 10)}…'
                                                : meeting.summary!.replaceAll(RegExp(r'[#*\n\r]'), '').trim(),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => MeetingDetailScreen(meetingId: meeting.id!),
                                        ),
                                      );
                                    },
                                    onLongPress: () => _showMeetingContextMenu(meeting),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
