import 'dart:convert';

/// 会议模型
/// 列表视图只加载索引字段（transcript/summary 为 null）
/// 详情视图通过 loadMeetingDetail 从文件加载完整内容
class Meeting {
  final int? id;
  final String title;
  final DateTime date;
  final String? transcript;
  final String? summary;
  final List<Participant> participants;
  final int recordingDuration;
  final String folderName;
  final String description;

  Meeting({
    this.id,
    required this.title,
    required this.date,
    this.transcript,
    this.summary,
    this.participants = const [],
    this.recordingDuration = 0,
    required this.folderName,
    this.description = '',
  });

  /// 索引视图：不加载 transcript/summary
  Map<String, dynamic> toIndexMap() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'recordingDuration': recordingDuration,
      'folderName': folderName,
      'description': description,
    };
  }

  Map<String, dynamic> toMap() => toIndexMap();

  Map<String, dynamic> toJson() => toMap();

  factory Meeting.fromMap(Map<String, dynamic> map) {
    List<Participant> parseParticipants(dynamic value) {
      if (value == null) return [];
      List<dynamic> list;
      if (value is String) {
        try {
          list = jsonDecode(value) as List<dynamic>;
        } catch (_) {
          return [];
        }
      } else if (value is List) {
        list = value;
      } else {
        return [];
      }
      return list
          .map((p) => Participant.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return Meeting(
      id: map['id'],
      title: map['title'] ?? '',
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      transcript: map['transcript'] as String?,
      summary: map['summary'] as String?,
      participants: parseParticipants(map['participants']),
      recordingDuration: map['recordingDuration'] as int? ?? 0,
      folderName: map['folderName'] ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting.fromMap(json);

  /// 生成文件夹名：{id}_{title}（清理非法字符）
  static String generateFolderName(int id, String title) {
    final cleaned = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final truncated = cleaned.length > 50 ? cleaned.substring(0, 50) : cleaned;
    return '${id}_$truncated';
  }
}

/// 会议完整内容（按需从文件加载）
class MeetingDetail {
  final Meeting meeting;
  final String transcript;
  final String summary;

  const MeetingDetail({
    required this.meeting,
    this.transcript = '',
    this.summary = '',
  });

  int? get id => meeting.id;
  String get title => meeting.title;
  DateTime get date => meeting.date;
  List<Participant> get participants => meeting.participants;
  int get recordingDuration => meeting.recordingDuration;
  String get folderName => meeting.folderName;
}

/// 会议文件元数据（meta.json 序列化）
class MeetingMeta {
  final String title;
  final DateTime date;
  final List<Participant> participants;
  final int recordingDuration;
  final String transcriptFile;
  final String summaryFile;
  final String recordingFile;

  MeetingMeta({
    required this.title,
    required this.date,
    this.participants = const [],
    this.recordingDuration = 0,
    this.transcriptFile = 'transcript.md',
    this.summaryFile = 'summary.md',
    this.recordingFile = 'recording.opus',
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'date': date.toIso8601String(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'recordingDuration': recordingDuration,
      'transcriptFile': transcriptFile,
      'summaryFile': summaryFile,
      'recordingFile': recordingFile,
    };
  }

  factory MeetingMeta.fromJson(Map<String, dynamic> json) {
    return MeetingMeta(
      title: json['title'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => Participant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      recordingDuration: json['recordingDuration'] as int? ?? 0,
      transcriptFile: json['transcriptFile'] ?? 'transcript.md',
      summaryFile: json['summaryFile'] ?? 'summary.md',
      recordingFile: json['recordingFile'] ?? 'recording.opus',
    );
  }
}

class Participant {
  final String id;
  final String name;
  final String? role;
  final String? voiceProfile;
  final bool isPresenter;
  final DateTime joinTime;

  Participant({
    required this.id,
    required this.name,
    this.role,
    this.voiceProfile,
    this.isPresenter = false,
    required this.joinTime,
  });

  Participant copyWith({
    String? id,
    String? name,
    String? role,
    String? voiceProfile,
    bool? isPresenter,
    DateTime? joinTime,
  }) {
    return Participant(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      voiceProfile: voiceProfile ?? this.voiceProfile,
      isPresenter: isPresenter ?? this.isPresenter,
      joinTime: joinTime ?? this.joinTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'voiceProfile': voiceProfile,
      'isPresenter': isPresenter,
      'joinTime': joinTime.toIso8601String(),
    };
  }

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String?,
      voiceProfile: json['voiceProfile'] as String?,
      isPresenter: json['isPresenter'] as bool? ?? false,
      joinTime:
          DateTime.tryParse(json['joinTime'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
