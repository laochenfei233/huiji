import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yanji/services/audio_recorder_service.dart';

class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key});

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  final AudioRecorderService _audioRecorder = AudioRecorderService();
  bool _isRecording = false;
  int _audioDataCount = 0;
  StreamSubscription? _audioStreamSubscription;

  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    super.dispose();
  }

  void _toggleRecording() async {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      try {
        await _audioRecorder.startRecording();

        // Listen to audio data stream
        _audioStreamSubscription = _audioRecorder.audioStream.listen(
          (audioData) {
            setState(() {
              _audioDataCount++;
            });
            print('Received audio data chunk ${_audioDataCount}: ${audioData.length} bytes');
          },
          onError: (error) {
            print('Audio stream error: $error');
            setState(() {
              _isRecording = false;
            });
          },
        );
      } catch (e) {
        print('Error starting recording: $e');
        setState(() {
          _isRecording = false;
        });
      }
    } else {
      await _audioRecorder.stopRecording();
      _audioStreamSubscription?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'WebRTC Audio Capture Test',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Status: ${_isRecording ? "Recording" : "Stopped"}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            Text(
              'Audio Chunks Received: $_audioDataCount',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _toggleRecording,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                _isRecording ? 'Stop Recording' : 'Start Recording',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}