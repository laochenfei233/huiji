import 'dart:async';
import 'dart:ui'; // 添加 Color 类
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // 添加 Colors 类
import 'package:yanji/models/meeting.dart';
import 'package:yanji/models/meeting_session.dart';
import 'package:yanji/services/storage_service.dart';

/// 会议会话事件类型
enum SessionEventType {
  created,
  updated,
  stateChanged,
  participantsChanged,
  transcriptReceived,
  summaryGenerated,
  completed,
  error,
}

/// 会议会话事件
class SessionEvent {
  final SessionEventType type;
  final String sessionId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  const SessionEvent({
    required this.type,
    required this.sessionId,
    this.data,
    required this.timestamp,
  });
}

/// 会议会话状态管理器
class MeetingSessionProvider extends ChangeNotifier {
  static final MeetingSessionProvider _instance = MeetingSessionProvider._internal();
  factory MeetingSessionProvider() => _instance;
  MeetingSessionProvider._internal();

  // 当前活动会话
  MeetingSession? _currentSession;
  
  // 会话历史记录
  final List<MeetingSession> _sessions = [];
  
  // 事件流控制器
  final StreamController<SessionEvent> _eventController = StreamController.broadcast();
  
  // 错误处理
  String? _lastError;
  bool _hasError = false;

  // Getters
  MeetingSession? get currentSession => _currentSession;
  List<MeetingSession> get sessions => List.unmodifiable(_sessions);
  Stream<SessionEvent> get events => _eventController.stream;
  String? get lastError => _lastError;
  bool get hasError => _hasError;
  bool get hasActiveSession => _currentSession != null;

  /// 创建新会议会话
  Future<MeetingSession> createSession({
    required String title,
    String description = '',
    String asrModelName = '',
    String summaryModelName = '',
    String? templateId,
  }) async {
    try {
      final session = MeetingSession.create(
        title: title,
        description: description,
        asrModelName: asrModelName,
        summaryModelName: summaryModelName,
        metadata: templateId != null ? {'templateId': templateId} : const {},
      );
      
      _currentSession = session;
      _sessions.add(session);
      _hasError = false;
      _lastError = null;
      
      notifyListeners();
      
      _emitEvent(SessionEventType.created, session.id, {
        'session': session,
      });
      
      return session;
      
    } catch (e) {
      _handleError('创建会话失败: $e');
      rethrow;
    }
  }

  /// 更新当前会话
  Future<void> updateSession(MeetingSession updatedSession) async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }
    
    try {
      final oldSession = _currentSession!;
      _currentSession = updatedSession.copyWith(
        updatedAt: DateTime.now(),
      );
      
      // 更新历史记录中的会话
      final index = _sessions.indexWhere((s) => s.id == updatedSession.id);
      if (index >= 0) {
        _sessions[index] = _currentSession!;
      }
      
      _hasError = false;
      _lastError = null;
      
      notifyListeners();
      
      _emitEvent(SessionEventType.updated, updatedSession.id, {
        'oldSession': oldSession,
        'newSession': _currentSession,
      });
      
    } catch (e) {
      _handleError('更新会话失败: $e');
      rethrow;
    }
  }

  /// 更新会话状态
  Future<void> updateSessionState(MeetingSessionState newState) async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }
    
    final oldState = _currentSession!.state;
    final updatedSession = _currentSession!.copyWith(
      state: newState,
      updatedAt: DateTime.now(),
    );
    
    await updateSession(updatedSession);
    
    _emitEvent(SessionEventType.stateChanged, _currentSession!.id, {
      'oldState': oldState,
      'newState': newState,
    });
  }

  /// 更新参与者信息
  Future<void> updateParticipants(List<Participant> participants) async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }
    
    final oldParticipants = _currentSession!.participants;
    final updatedSession = _currentSession!.copyWith(
      participants: participants,
      updatedAt: DateTime.now(),
    );
    
    await updateSession(updatedSession);
    
    _emitEvent(SessionEventType.participantsChanged, _currentSession!.id, {
      'oldParticipants': oldParticipants,
      'newParticipants': participants,
    });
  }

  /// 更新转录文本
  Future<void> updateTranscript(String transcript) async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }
    
    final oldTranscript = _currentSession!.originalTranscript;
    final updatedSession = _currentSession!.copyWith(
      originalTranscript: transcript,
      state: MeetingSessionState.transcription,
      updatedAt: DateTime.now(),
    );
    
    await updateSession(updatedSession);
    
    _emitEvent(SessionEventType.transcriptReceived, _currentSession!.id, {
      'oldTranscript': oldTranscript,
      'newTranscript': transcript,
    });
  }

  /// 更新总结文本
  Future<void> updateSummary(String summary) async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }
    
    final oldSummary = _currentSession!.summaryText;
    final updatedSession = _currentSession!.copyWith(
      summaryText: summary,
      state: MeetingSessionState.summary,
      updatedAt: DateTime.now(),
    );
    
    await updateSession(updatedSession);
    
    _emitEvent(SessionEventType.summaryGenerated, _currentSession!.id, {
      'oldSummary': oldSummary,
      'newSummary': summary,
    });
  }

  /// 自动保存当前会话到数据库（每步完成后调用）
  Future<void> autoSave() async {
    if (_currentSession == null) return;

    try {
      final storage = StorageService();
      final existingId = _currentSession!.metadata['savedMeetingId'] as int?;
      final transcript = _currentSession!.originalTranscript;
      final summary = _currentSession!.summaryText ?? '';

      final meeting = Meeting(
        id: existingId,
        title: _currentSession!.title,
        date: _currentSession!.createdAt,
        transcript: transcript,
        summary: summary,
        participants: _currentSession!.participants,
        recordingDuration: _currentSession!.recordingDuration,
        folderName: _currentSession!.metadata['folderName'] as String? ?? '',
      );

      int savedId;
      if (existingId != null) {
        await storage.updateMeeting(meeting);
        // 更新文件内容
        if (transcript.isNotEmpty) await storage.saveTranscript(existingId, transcript);
        if (summary.isNotEmpty) await storage.saveSummary(existingId, summary);
        savedId = existingId;
      } else {
        savedId = await storage.saveMeeting(meeting);
        // 记录已保存的 id 和 folderName 到 session metadata
        final savedMeeting = await storage.loadMeeting(savedId);
        _currentSession = _currentSession!.copyWith(
          metadata: {
            ..._currentSession!.metadata,
            'savedMeetingId': savedId,
            'folderName': savedMeeting?.folderName ?? '',
          },
        );
        notifyListeners();
      }
    } catch (e, stackTrace) {
      print('自动保存失败: $e');
      print('堆栈: $stackTrace');
    }
  }

  /// 完成会话
  Future<void> completeSession() async {
    if (_currentSession == null) {
      _handleError('没有活动会话');
      return;
    }

    final updatedSession = _currentSession!.copyWith(
      state: MeetingSessionState.completed,
      updatedAt: DateTime.now(),
    );

    await updateSession(updatedSession);

    // 持久化到 StorageService（复用 autoSave 已保存的 id，避免重复）
    try {
      final storage = StorageService();
      final existingId = _currentSession!.metadata['savedMeetingId'] as int?;
      final transcript = _currentSession!.originalTranscript;
      final summary = _currentSession!.summaryText ?? '';

      final meeting = Meeting(
        id: existingId,
        title: _currentSession!.title,
        date: _currentSession!.createdAt,
        transcript: transcript,
        summary: summary,
        participants: _currentSession!.participants,
        recordingDuration: _currentSession!.recordingDuration,
        folderName: _currentSession!.metadata['folderName'] as String? ?? '',
      );
      if (existingId != null) {
        await storage.updateMeeting(meeting);
        if (transcript.isNotEmpty) await storage.saveTranscript(existingId, transcript);
        if (summary.isNotEmpty) await storage.saveSummary(existingId, summary);
      } else {
        await storage.saveMeeting(meeting);
      }
    } catch (e, stackTrace) {
      print('保存会议到数据库失败: $e');
      print('堆栈: $stackTrace');
    }

    _emitEvent(SessionEventType.completed, _currentSession!.id, {
      'session': _currentSession,
    });
  }

  /// 结束当前会话（但不清除）
  Future<void> endCurrentSession() async {
    if (_currentSession != null) {
      final sessionId = _currentSession!.id;
      _currentSession = null;
      notifyListeners();
      
      _emitEvent(SessionEventType.error, sessionId, {
        'message': '会话已结束',
      });
    }
  }

  /// 清除当前会话
  void clearCurrentSession() {
    _currentSession = null;
    _hasError = false;
    _lastError = null;
    notifyListeners();
  }

  /// 从历史记录加载会话
  Future<MeetingSession?> loadSession(String sessionId) async {
    final session = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => null as MeetingSession,
    );
    
    if (session != null) {
      _currentSession = session;
      notifyListeners();
      return session;
    }
    
    _handleError('未找到会话: $sessionId');
    return null;
  }

  /// 删除会话
  Future<void> deleteSession(String sessionId) async {
    try {
      _sessions.removeWhere((s) => s.id == sessionId);
      
      if (_currentSession?.id == sessionId) {
        _currentSession = null;
      }
      
      notifyListeners();
      
    } catch (e) {
      _handleError('删除会话失败: $e');
      rethrow;
    }
  }

  /// 获取会话进度
  double getSessionProgress() {
    return _currentSession?.progress ?? 0.0;
  }

  /// 检查会话是否完成
  bool isSessionComplete() {
    return _currentSession?.isComplete ?? false;
  }

  /// 检查是否有转录内容
  bool hasTranscript() {
    return _currentSession?.hasTranscript ?? false;
  }

  /// 检查是否有总结内容
  bool hasSummary() {
    return _currentSession?.hasSummary ?? false;
  }

  /// 获取会话统计信息
  SessionStatistics getSessionStatistics() {
    if (_currentSession == null) {
      return const SessionStatistics(
        totalDuration: 0,
        participantCount: 0,
        wordCount: 0,
        questionCount: 0,
        averageConfidence: 0.0,
        speakerStats: {},
      );
    }
    
    return SessionStatistics.fromSession(_currentSession!);
  }

  /// 导出会话数据
  Map<String, dynamic> exportSessionData() {
    if (_currentSession == null) {
      throw StateError('没有活动会话可导出');
    }
    
    return {
      'session': _currentSession!.toJson(),
      'statistics': getSessionStatistics().toJson(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  /// 导入会话数据
  Future<void> importSessionData(Map<String, dynamic> data) async {
    try {
      final sessionData = data['session'] as Map<String, dynamic>;
      final session = MeetingSession.fromJson(sessionData);
      
      _sessions.add(session);
      _currentSession = session;
      
      notifyListeners();
      
    } catch (e) {
      _handleError('导入会话数据失败: $e');
      rethrow;
    }
  }

  /// 清除错误状态
  void clearError() {
    _hasError = false;
    _lastError = null;
    notifyListeners();
  }

  void _emitEvent(SessionEventType type, String sessionId, [Map<String, dynamic>? data]) {
    final event = SessionEvent(
      type: type,
      sessionId: sessionId,
      data: data,
      timestamp: DateTime.now(),
    );
    
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _handleError(String error) {
    _hasError = true;
    _lastError = error;
    notifyListeners();
    
    if (_currentSession != null) {
      _emitEvent(SessionEventType.error, _currentSession!.id, {
        'error': error,
      });
    }
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}

/// 全局会话提供者实例
final meetingSessionProvider = MeetingSessionProvider();

/// 会话助手类
class SessionHelper {
  static MeetingSessionProvider get provider => meetingSessionProvider;
  
  /// 快速创建并开始会话
  static Future<MeetingSession> quickStart({
    required String title,
    String asrModel = '',
    String summaryModel = '',
  }) async {
    return await provider.createSession(
      title: title,
      asrModelName: asrModel,
      summaryModelName: summaryModel,
    );
  }
  
  /// 获取当前会话的下一个状态
  static MeetingSessionState? getNextState(MeetingSessionState currentState) {
    return switch (currentState) {
      MeetingSessionState.setup => MeetingSessionState.recording,
      MeetingSessionState.recording => MeetingSessionState.transcription,
      MeetingSessionState.transcription => MeetingSessionState.summary,
      MeetingSessionState.summary => MeetingSessionState.completed,
      MeetingSessionState.completed => null,
    };
  }
  
  /// 检查状态转换是否有效
  static bool isValidStateTransition(
    MeetingSessionState from,
    MeetingSessionState to,
  ) {
    return getNextState(from) == to;
  }
  
  /// 获取状态显示名称
  static String getStateDisplayName(MeetingSessionState state) {
    return switch (state) {
      MeetingSessionState.setup => '设置',
      MeetingSessionState.recording => '录音',
      MeetingSessionState.transcription => '转录',
      MeetingSessionState.summary => '总结',
      MeetingSessionState.completed => '完成',
    };
  }
  
  /// 获取状态颜色
  static Color getStateColor(MeetingSessionState state) {
    return switch (state) {
      MeetingSessionState.setup => Colors.blue,
      MeetingSessionState.recording => Colors.red,
      MeetingSessionState.transcription => Colors.orange,
      MeetingSessionState.summary => Colors.green,
      MeetingSessionState.completed => Colors.grey,
    };
  }
}