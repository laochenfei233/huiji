import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  File? _logFile;
  final List<String> _logBuffer = [];
  static const int _bufferSize = 100;

  Future<void> init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/app_logs.txt');
      
      // 创建文件（如果不存在）
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }
      
      // 写入初始化日志
      _writeLog('Logging service initialized at ${DateTime.now()}');
    } catch (e) {
      debugPrint('Failed to initialize logging service: $e');
    }
  }

  void log(String message, {LogLevel level = LogLevel.info}) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] [${level.name.toUpperCase()}] $message';
    
    // 添加到缓冲区
    _logBuffer.add(logEntry);
    
    // 保持缓冲区大小
    if (_logBuffer.length > _bufferSize) {
      _logBuffer.removeAt(0);
    }
    
    // 输出到控制台
    debugPrint(logEntry);
    
    // 写入文件
    _writeLog(logEntry);
  }

  void logError(String message, dynamic error, StackTrace? stackTrace) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] [ERROR] $message\nError: $error\nStack trace: $stackTrace';
    
    // 添加到缓冲区
    _logBuffer.add(logEntry);
    
    // 保持缓冲区大小
    if (_logBuffer.length > _bufferSize) {
      _logBuffer.removeAt(0);
    }
    
    // 输出到控制台
    debugPrint(logEntry);
    
    // 写入文件
    _writeLog(logEntry);
  }

  Future<void> _writeLog(String logEntry) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString('$logEntry\n', mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('Failed to write log to file: $e');
    }
  }

  Future<List<String>> getLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        final content = await _logFile!.readAsString();
        return content.split('\n')..removeWhere((line) => line.isEmpty);
      }
      return List.unmodifiable(_logBuffer);
    } catch (e) {
      debugPrint('Failed to read logs: $e');
      return List.unmodifiable(_logBuffer);
    }
  }

  Future<void> clearLogs() async {
    try {
      _logBuffer.clear();
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      debugPrint('Failed to clear logs: $e');
    }
  }
}

enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
}