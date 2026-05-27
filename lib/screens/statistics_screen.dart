import 'package:flutter/material.dart';
import 'package:yanji/services/storage_service.dart';
import 'package:yanji/models/meeting.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StorageService _storageService = StorageService();
  late Future<List<Meeting>> _meetingsFuture;
  int _totalMeetings = 0;
  int _totalWords = 0;
  int _totalParticipants = 0;
  double _avgWordsPerMeeting = 0.0;

  @override
  void initState() {
    super.initState();
    _meetingsFuture = _storageService.loadMeetings();
    _calculateStatistics();
  }

  Future<void> _calculateStatistics() async {
    final meetings = await _meetingsFuture;
    
    int totalWords = 0;
    int totalParticipants = 0;
    
    for (var meeting in meetings) {
      // Count words in transcript
      totalWords += (meeting.transcript ?? '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      totalParticipants += meeting.participants.length;
    }
    
    setState(() {
      _totalMeetings = meetings.length;
      _totalWords = totalWords;
      _totalParticipants = totalParticipants;
      _avgWordsPerMeeting = meetings.isNotEmpty ? totalWords / meetings.length : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议统计'),
      ),
      body: FutureBuilder<List<Meeting>>(
        future: _meetingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text(
                                  '总会议数',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '$_totalMeetings',
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text(
                                  '总字数',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '$_totalWords',
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text(
                                  '总参与者',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '$_totalParticipants',
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text(
                                  '平均每会议字数',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${_avgWordsPerMeeting.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '最近会议',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: snapshot.data!.length > 5 ? 5 : snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final meeting = snapshot.data![index];
                        final wordCount = (meeting.transcript ?? '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
                        return Card(
                          child: ListTile(
                            title: Text(meeting.title),
                            subtitle: Text(
                              '${meeting.date.year}-${meeting.date.month.toString().padLeft(2, '0')}-${meeting.date.day.toString().padLeft(2, '0')}',
                            ),
                            trailing: Text('$wordCount 字'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}