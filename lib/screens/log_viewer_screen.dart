import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yanji/services/logging_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final LoggingService _loggingService = LoggingService();
  List<String> _logs = [];
  Timer? _timer;
  ScrollController? _scrollController;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadLogs();
    // 每秒刷新一次日志
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _loadLogs();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await _loggingService.getLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
        });
        
        // 自动滚动到底部
        if (_autoScroll && _scrollController != null && _logs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController!.hasClients) {
              _scrollController!.animateTo(
                _scrollController!.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading logs: $e');
    }
  }

  Future<void> _clearLogs() async {
    await _loggingService.clearLogs();
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用日志'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              '日志条目: ${_logs.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('暂无日志'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            log,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadLogs,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}