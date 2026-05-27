import 'package:yanji/models/meeting.dart';

/// 会议会话状态
enum MeetingSessionState {
  setup,
  recording,
  transcription,
  summary,
  completed,
}

/// 会议会话
class MeetingSession {
  final String id;
  final String title;
  final String description;
  final List<Participant> participants;
  final String asrModelName;
  final String summaryModelName;
  final String originalTranscript;
  final String? summaryText;
  final int recordingDuration;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MeetingSessionState state;
  final Map<String, dynamic> metadata;
  
  const MeetingSession({
    required this.id,
    required this.title,
    this.description = '',
    this.participants = const [],
    this.asrModelName = '',
    this.summaryModelName = '',
    this.originalTranscript = '',
    this.summaryText,
    this.recordingDuration = 0,
    required this.createdAt,
    required this.updatedAt,
    this.state = MeetingSessionState.setup,
    this.metadata = const {},
  });
  
  bool get isComplete => state == MeetingSessionState.completed;
  bool get hasTranscript => originalTranscript.isNotEmpty;
  bool get hasSummary => summaryText != null && summaryText!.isNotEmpty;
  int get participantCount => participants.length;
  double get progress => switch (state) {
    MeetingSessionState.setup => 0.0,
    MeetingSessionState.recording => 0.33,
    MeetingSessionState.transcription => 0.67,
    MeetingSessionState.summary => 1.0,
    MeetingSessionState.completed => 1.0,
  };
  
  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'participants': participants.map((p) => p.toJson()).toList(),
      'asrModelName': asrModelName,
      'summaryModelName': summaryModelName,
      'originalTranscript': originalTranscript,
      'summaryText': summaryText,
      'recordingDuration': recordingDuration,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'state': state.index,
      'metadata': metadata,
    };
  }
  
  /// 从JSON创建实例
  factory MeetingSession.fromJson(Map<String, dynamic> json) {
    return MeetingSession(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      participants: (json['participants'] as List<dynamic>?)
          ?.map((p) => Participant.fromJson(p as Map<String, dynamic>))
          .toList() ?? const [],
      asrModelName: json['asrModelName'] as String? ?? '',
      summaryModelName: json['summaryModelName'] as String? ?? '',
      originalTranscript: json['originalTranscript'] as String? ?? '',
      summaryText: json['summaryText'] as String?,
      recordingDuration: json['recordingDuration'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      state: MeetingSessionState.values[json['state'] as int? ?? 0],
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
  
  /// 创建副本
  MeetingSession copyWith({
    String? id,
    String? title,
    String? description,
    List<Participant>? participants,
    String? asrModelName,
    String? summaryModelName,
    String? originalTranscript,
    String? summaryText,
    int? recordingDuration,
    DateTime? createdAt,
    DateTime? updatedAt,
    MeetingSessionState? state,
    Map<String, dynamic>? metadata,
  }) {
    return MeetingSession(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      participants: participants ?? this.participants,
      asrModelName: asrModelName ?? this.asrModelName,
      summaryModelName: summaryModelName ?? this.summaryModelName,
      originalTranscript: originalTranscript ?? this.originalTranscript,
      summaryText: summaryText ?? this.summaryText,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
      metadata: metadata ?? this.metadata,
    );
  }
  
  /// 创建新会话
  factory MeetingSession.create({
    required String title,
    String description = '',
    String asrModelName = '',
    String summaryModelName = '',
    Map<String, dynamic> metadata = const {},
  }) {
    final now = DateTime.now();
    return MeetingSession(
      id: 'meeting_${now.millisecondsSinceEpoch}',
      title: title,
      description: description,
      participants: const [],
      asrModelName: asrModelName,
      summaryModelName: summaryModelName,
      createdAt: now,
      updatedAt: now,
      state: MeetingSessionState.setup,
      metadata: metadata,
    );
  }
  
  @override
  String toString() {
    return 'MeetingSession(id: $id, title: $title, state: $state, participants: $participantCount)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MeetingSession &&
        other.id == id &&
        other.title == title &&
        other.state == state;
  }
  
  @override
  int get hashCode {
    return id.hashCode ^ title.hashCode ^ state.hashCode;
  }
}
class SessionStatistics {
  final int totalDuration;
  final int participantCount;
  final int wordCount;
  final int questionCount;
  final double averageConfidence;
  final Map<String, int> speakerStats;
  
  const SessionStatistics({
    required this.totalDuration,
    required this.participantCount,
    required this.wordCount,
    required this.questionCount,
    required this.averageConfidence,
    required this.speakerStats,
  });
  
  factory SessionStatistics.fromSession(MeetingSession session) {
    final words = session.originalTranscript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    
    return SessionStatistics(
      totalDuration: session.recordingDuration,
      participantCount: session.participantCount,
      wordCount: words,
      questionCount: 0, // 需要从转录中提取问题数量
      averageConfidence: 0.95, // 模拟值
      speakerStats: {}, // 需要分析转录文本
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'totalDuration': totalDuration,
      'participantCount': participantCount,
      'wordCount': wordCount,
      'questionCount': questionCount,
      'averageConfidence': averageConfidence,
      'speakerStats': speakerStats,
    };
  }
  
  factory SessionStatistics.fromJson(Map<String, dynamic> json) {
    return SessionStatistics(
      totalDuration: json['totalDuration'] as int,
      participantCount: json['participantCount'] as int,
      wordCount: json['wordCount'] as int,
      questionCount: json['questionCount'] as int,
      averageConfidence: (json['averageConfidence'] as num).toDouble(),
      speakerStats: Map<String, int>.from(json['speakerStats'] as Map),
    );
  }
}