import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:yanji/services/storage_service.dart';

class MeetingPlaybackScreen extends StatefulWidget {
  final int meetingId;
  final String title;

  const MeetingPlaybackScreen({
    super.key,
    required this.meetingId,
    required this.title,
  });

  @override
  State<MeetingPlaybackScreen> createState() => _MeetingPlaybackScreenState();
}

class _MeetingPlaybackScreenState extends State<MeetingPlaybackScreen> {
  final StorageService _storageService = StorageService();
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _transcript = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final path = await _storageService.getRecordingPath(widget.meetingId);
      final detail = await _storageService.loadMeetingDetail(widget.meetingId);

      if (detail == null) {
        setState(() {
          _isLoading = false;
          _error = '会议不存在';
        });
        return;
      }

      setState(() {
        _transcript = detail.transcript;
        _isLoading = false;
      });

      if (path != null) {
        _initPlayer(path);
      } else {
        setState(() => _error = '未找到录音文件');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '加载失败: $e';
      });
    }
  }

  void _initPlayer(String path) {
    _audioPlayer = AudioPlayer();

    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer!.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _audioPlayer!.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });

    _audioPlayer!.setSource(DeviceFileSource(path));
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _togglePlay() async {
    if (_audioPlayer == null) return;
    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.resume();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    if (_audioPlayer == null) return;
    final newPos = _position + Duration(seconds: seconds);
    final clamped = newPos.isNegative ? Duration.zero : newPos;
    await _audioPlayer!.seek(clamped > _duration ? _duration : clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 播放器区域
                    _buildPlayer(),
                    const Divider(height: 1),
                    // 会议原文
                    Expanded(
                      child: _buildTranscript(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPlayer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 进度条
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _position.inMilliseconds.toDouble().clamp(
                0.0,
                _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
              ),
              onChanged: (v) => _audioPlayer?.seek(Duration(milliseconds: v.toInt())),
            ),
          ),
          // 时间
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 28,
                onPressed: () => _seekRelative(-10),
                tooltip: '后退10秒',
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: _togglePlay,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 28,
                onPressed: () => _seekRelative(10),
                tooltip: '快进10秒',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTranscript() {
    if (_transcript.isEmpty) {
      return const Center(
        child: Text('暂无转录文本', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '会议原文',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              _transcript,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
