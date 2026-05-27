import 'package:flutter/material.dart';
import 'package:yanji/models/meeting.dart';

class ParticipantScreen extends StatefulWidget {
  final List<Participant> participants;
  final Function(Participant) onParticipantAdded;
  final Function(String) onParticipantRemoved;

  const ParticipantScreen({
    super.key,
    required this.participants,
    required this.onParticipantAdded,
    required this.onParticipantRemoved,
  });

  @override
  State<ParticipantScreen> createState() => _ParticipantScreenState();
}

class _ParticipantScreenState extends State<ParticipantScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _addParticipant() {
    if (_nameController.text.isNotEmpty) {
      final participant = Participant(
        id: _nameController.text,
        name: _nameController.text,
        joinTime: DateTime.now(),
      );
      widget.onParticipantAdded(participant);
      _nameController.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('参与者已添加')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议参与者'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '添加参与者',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '参与者姓名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addParticipant,
              child: const Text('添加参与者'),
            ),
            const SizedBox(height: 20),
            const Text(
              '当前参与者',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: widget.participants.length,
                itemBuilder: (context, index) {
                  final participant = widget.participants[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text(participant.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          widget.onParticipantRemoved(participant.id);
                        },
                      ),
                    ),
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