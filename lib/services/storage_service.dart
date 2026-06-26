import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yanji/models/meeting.dart';

class StorageService {
  static Database? _database;
  static SharedPreferences? _prefs;
  static const _meetingsKey = 'stored_meetings';

  /// meetings 根目录
  static Future<Directory> getMeetingsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(join(docs.path, 'meetings'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Web 平台不支持 SQLite');
    }
    if (_database != null) return _database!;
    _database = await _initDB();
    // 检查并修复表结构
    await _ensureCorrectSchema(_database!);
    return _database!;
  }

  /// 确保表结构正确（删除多余列，添加缺失列）
  Future<void> _ensureCorrectSchema(Database db) async {
    try {
      final columns = await db.rawQuery('PRAGMA table_info(meetings)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      debugPrint('[DB] 当前列: $columnNames');

      // 需要的列
      final requiredColumns = ['id', 'title', 'date', 'folderName', 'participants', 'recordingDuration', 'description'];

      // 检查是否需要修复
      final hasFolderName = columnNames.contains('folderName');
      final hasDescription = columnNames.contains('description');
      final hasExtraColumns = columnNames.any((c) => !requiredColumns.contains(c));

      if (hasFolderName && hasDescription && !hasExtraColumns) return;

      debugPrint('[DB] 需要修复表结构...');

      // 重建表
      await db.transaction((txn) async {
        // 创建新表
        await txn.execute('''
          CREATE TABLE meetings_clean (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            date TEXT,
            folderName TEXT,
            participants TEXT,
            recordingDuration INTEGER DEFAULT 0,
            description TEXT DEFAULT ''
          )
        ''');

        // 复制数据（只复制需要的列）
        if (hasFolderName) {
          if (hasDescription) {
            await txn.execute('''
              INSERT INTO meetings_clean (id, title, date, folderName, participants, recordingDuration, description)
              SELECT id, title, date, folderName, participants, recordingDuration, description FROM meetings
            ''');
          } else {
            await txn.execute('''
              INSERT INTO meetings_clean (id, title, date, folderName, participants, recordingDuration)
              SELECT id, title, date, folderName, participants, recordingDuration FROM meetings
            ''');
          }
        } else {
          // 旧表没有 folderName，需要生成
          await txn.execute('''
            INSERT INTO meetings_clean (id, title, date, participants, recordingDuration)
            SELECT id, title, date, participants, recordingDuration FROM meetings
          ''');

          // 为每行生成 folderName
          final rows = await txn.query('meetings_clean');
          for (final row in rows) {
            final id = row['id'] as int;
            final title = row['title'] as String? ?? '';
            final folderName = Meeting.generateFolderName(id, title);
            await txn.update(
              'meetings_clean',
              {'folderName': folderName},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }

        // 删除旧表
        await txn.execute('DROP TABLE meetings');

        // 重命名新表
        await txn.execute('ALTER TABLE meetings_clean RENAME TO meetings');
      });

      debugPrint('[DB] 表结构修复完成');
    } catch (e) {
      debugPrint('[DB] 修复表结构失败: $e');
    }
  }

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Directory> getDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  // ==================== SQLite 初始化 + 迁移 ====================

  Future<Database> _initDB() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'meetings.db');

    try {
      return await openDatabase(
        path,
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE meetings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              date TEXT,
              folderName TEXT,
              participants TEXT,
              recordingDuration INTEGER DEFAULT 0,
              description TEXT DEFAULT ''
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 4) {
            // 旧版本迁移到新结构
            await _migrateFromOldSchema(db);
          }
        },
      );
    } catch (e) {
      debugPrint('Error opening database: $e');
      rethrow;
    }
  }

  /// 从旧 schema 迁移数据
  Future<void> _migrateFromOldSchema(Database db) async {
    // 检查旧表是否有 folderName 列
    final columns = await db.rawQuery('PRAGMA table_info(meetings)');
    final hasFolderName = columns.any((c) => c['name'] == 'folderName');

    if (hasFolderName) return; // 已迁移

    // 添加 folderName 列
    await db.execute('ALTER TABLE meetings ADD COLUMN folderName TEXT');

    // 只查询需要的列，避免 CursorWindow 溢出
    final oldMeetings = await db.query(
      'meetings',
      columns: ['id', 'title', 'date', 'participants', 'recordingDuration'],
    );

    final meetingsRoot = await getMeetingsRoot();

    for (final row in oldMeetings) {
      final id = row['id'] as int;
      final title = row['title'] as String? ?? '';

      // 创建文件夹
      final folderName = Meeting.generateFolderName(id, title);
      final folder = Directory(join(meetingsRoot.path, folderName));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // 写 meta.json
      final meta = MeetingMeta(
        title: title,
        date: DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now(),
        participants: (row['participants'] != null)
            ? (jsonDecode(row['participants'] as String) as List)
                .map((p) => Participant.fromJson(p as Map<String, dynamic>))
                .toList()
            : [],
        recordingDuration: row['recordingDuration'] as int? ?? 0,
      );
      await File(join(folder.path, 'meta.json'))
          .writeAsString(jsonEncode(meta.toJson()));

      // 更新 folderName
      await db.update(
        'meetings',
        {'folderName': folderName},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ==================== CRUD 操作 ====================

  Future<int> saveMeeting(Meeting meeting) async {
    if (kIsWeb) return _saveMeetingWeb(meeting);
    final db = await database;

    debugPrint('[Storage] saveMeeting: title=${meeting.title}');

    // 先插入获取 ID
    final map = meeting.toIndexMap();
    map.remove('id');
    map['participants'] = jsonEncode(map['participants']);
    final id = await db.insert('meetings', map);

    // 创建文件夹
    final folderName = Meeting.generateFolderName(id, meeting.title);
    final meetingsRoot = await getMeetingsRoot();
    final folder = Directory(join(meetingsRoot.path, folderName));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    // 写 meta.json
    final meta = MeetingMeta(
      title: meeting.title,
      date: meeting.date,
      participants: meeting.participants,
      recordingDuration: meeting.recordingDuration,
    );
    await File(join(folder.path, 'meta.json'))
        .writeAsString(jsonEncode(meta.toJson()));

    // 写 transcript.md（如果有）
    if (meeting.transcript != null && meeting.transcript!.isNotEmpty) {
      await File(join(folder.path, 'transcript.md'))
          .writeAsString(meeting.transcript!);
    }

    // 写 summary.md（如果有）
    if (meeting.summary != null && meeting.summary!.isNotEmpty) {
      await File(join(folder.path, 'summary.md'))
          .writeAsString(meeting.summary!);
    }

    // 更新 folderName
    await db.update(
      'meetings',
      {'folderName': folderName},
      where: 'id = ?',
      whereArgs: [id],
    );

    return id;
  }

  Future<int> _saveMeetingWeb(Meeting meeting) async {
    final p = await prefs;
    final list = _loadMeetingsFromPrefs(p);
    final newId = DateTime.now().millisecondsSinceEpoch;
    final meetingWithId = Meeting(
      id: newId,
      title: meeting.title,
      date: meeting.date,
      transcript: meeting.transcript,
      summary: meeting.summary,
      participants: meeting.participants,
      recordingDuration: meeting.recordingDuration,
      folderName: meeting.folderName.isNotEmpty
          ? meeting.folderName
          : Meeting.generateFolderName(newId, meeting.title),
    );
    list.add(meetingWithId);
    await p.setString(
        _meetingsKey, jsonEncode(list.map((m) => m.toMap()).toList()));
    return newId;
  }

  Future<int> updateMeeting(Meeting meeting) async {
    if (kIsWeb) return _updateMeetingWeb(meeting);
    final db = await database;
    final map = meeting.toIndexMap();
    map['participants'] = jsonEncode(map['participants']);
    try {
      return await db.update(
        'meetings',
        map,
        where: 'id = ?',
        whereArgs: [meeting.id],
      );
    } catch (e) {
      debugPrint('更新会议失败: $e');
      rethrow;
    }
  }

  Future<int> _updateMeetingWeb(Meeting meeting) async {
    final p = await prefs;
    final list = _loadMeetingsFromPrefs(p);
    final idx = list.indexWhere((m) => m.id == meeting.id);
    if (idx < 0) return 0;
    list[idx] = meeting;
    await p.setString(
        _meetingsKey, jsonEncode(list.map((m) => m.toMap()).toList()));
    return 1;
  }

  Future<int> deleteMeeting(int id) async {
    if (kIsWeb) return _deleteMeetingWeb(id);
    final db = await database;

    // 先查出 folderName 以删除文件夹
    final rows = await db.query('meetings',
        columns: ['folderName'], where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final folderName = rows.first['folderName'] as String?;
      if (folderName != null && folderName.isNotEmpty) {
        final meetingsRoot = await getMeetingsRoot();
        final folder = Directory(join(meetingsRoot.path, folderName));
        if (await folder.exists()) {
          await folder.delete(recursive: true);
        }
      }
    }

    return await db.delete('meetings', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> _deleteMeetingWeb(int id) async {
    final p = await prefs;
    final list = _loadMeetingsFromPrefs(p);
    list.removeWhere((m) => m.id == id);
    await p.setString(
        _meetingsKey, jsonEncode(list.map((m) => m.toMap()).toList()));
    return 1;
  }

  /// 加载会议列表（只加载索引字段，极快）
  Future<List<Meeting>> loadMeetings() async {
    if (kIsWeb) return _loadMeetingsFromPrefs(await prefs);
    final db = await database;

    // 调试：打印表结构
    final columns = await db.rawQuery('PRAGMA table_info(meetings)');
    debugPrint('[DB] 表结构: ${columns.map((c) => c['name']).toList()}');

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'meetings',
        columns: ['id', 'title', 'date', 'participants', 'recordingDuration', 'folderName'],
        orderBy: 'date DESC',
      );
      return List.generate(maps.length, (i) => Meeting.fromMap(maps[i]));
    } catch (e) {
      debugPrint('loadMeetings error: $e');
      // 尝试只加载 id 和 title
      try {
        final List<Map<String, dynamic>> maps = await db.query(
          'meetings',
          columns: ['id', 'title'],
          orderBy: 'id DESC',
        );
        return List.generate(maps.length, (i) => Meeting.fromMap(maps[i]));
      } catch (e2) {
        debugPrint('loadMeetings fallback error: $e2');
        return [];
      }
    }
  }

  List<Meeting> _loadMeetingsFromPrefs(SharedPreferences p) {
    final raw = p.getString(_meetingsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((m) => Meeting.fromMap(m)).toList();
  }

  /// 加载会议索引
  Future<Meeting?> loadMeeting(int id) async {
    if (kIsWeb) return _loadMeetingWeb(id);
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'meetings',
      columns: ['id', 'title', 'date', 'participants', 'recordingDuration', 'folderName'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Meeting.fromMap(maps.first);
    }
    return null;
  }

  Future<Meeting?> _loadMeetingWeb(int id) async {
    final list = _loadMeetingsFromPrefs(await prefs);
    try {
      return list.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 加载会议完整内容（索引 + 文件）
  Future<MeetingDetail?> loadMeetingDetail(int id) async {
    final meeting = await loadMeeting(id);
    if (meeting == null) return null;

    String transcript = '';
    String summary = '';

    try {
      final folder = await _getMeetingFolder(meeting);
      if (folder != null && await folder.exists()) {
        final transcriptFile = File(join(folder.path, 'transcript.md'));
        if (await transcriptFile.exists()) {
          transcript = await transcriptFile.readAsString();
        }
        final summaryFile = File(join(folder.path, 'summary.md'));
        if (await summaryFile.exists()) {
          summary = await summaryFile.readAsString();
        }
      }
    } catch (e) {
      debugPrint('加载会议内容失败: $e');
    }

    return MeetingDetail(
      meeting: meeting,
      transcript: transcript,
      summary: summary,
    );
  }

  Future<Meeting> getMeetingById(int id) async {
    final meeting = await loadMeeting(id);
    if (meeting == null) {
      throw Exception('Meeting not found with id: $id');
    }
    return meeting;
  }

  // ==================== 文件读写 ====================

  /// 获取会议文件夹
  Future<Directory?> _getMeetingFolder(Meeting meeting) async {
    if (meeting.folderName.isEmpty) return null;
    final meetingsRoot = await getMeetingsRoot();
    return Directory(join(meetingsRoot.path, meeting.folderName));
  }

  /// 获取会议文件夹路径
  Future<String?> getMeetingFolderPath(int meetingId) async {
    final meeting = await loadMeeting(meetingId);
    if (meeting == null) return null;
    final folder = await _getMeetingFolder(meeting);
    return folder?.path;
  }

  /// 保存 transcript 到文件
  Future<void> saveTranscript(int meetingId, String text) async {
    final meeting = await loadMeeting(meetingId);
    if (meeting == null) return;
    final folder = await _getMeetingFolder(meeting);
    if (folder == null) return;
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    await File(join(folder.path, 'transcript.md')).writeAsString(text);
  }

  /// 保存 summary 到文件
  Future<void> saveSummary(int meetingId, String text) async {
    final meeting = await loadMeeting(meetingId);
    if (meeting == null) return;
    final folder = await _getMeetingFolder(meeting);
    if (folder == null) return;
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    await File(join(folder.path, 'summary.md')).writeAsString(text);
  }

  /// 检查会议是否有录音文件
  Future<bool> hasRecording(int meetingId) async {
    final meeting = await loadMeeting(meetingId);
    if (meeting == null) return false;
    final folder = await _getMeetingFolder(meeting);
    if (folder == null) return false;
    final opusFile = File(join(folder.path, 'recording.opus'));
    if (opusFile.existsSync()) return true;
    final wavFile = File(join(folder.path, 'recording.wav'));
    return wavFile.existsSync();
  }

  /// 获取录音文件路径
  Future<String?> getRecordingPath(int meetingId) async {
    final meeting = await loadMeeting(meetingId);
    if (meeting == null) return null;
    final folder = await _getMeetingFolder(meeting);
    if (folder == null) return null;
    final opusPath = join(folder.path, 'recording.opus');
    if (File(opusPath).existsSync()) return opusPath;
    final wavPath = join(folder.path, 'recording.wav');
    if (File(wavPath).existsSync()) return wavPath;
    return null;
  }

  /// 计算存储占用（bytes）
  Future<int> calculateStorageUsage() async {
    int totalBytes = 0;
    try {
      final meetingsRoot = await getMeetingsRoot();
      if (await meetingsRoot.exists()) {
        await for (final entity in meetingsRoot.list(recursive: true)) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  /// 获取所有会议文件夹路径（用于云导出）
  Future<List<MeetingFolderInfo>> getAllMeetingFolders() async {
    final meetings = await loadMeetings();
    final result = <MeetingFolderInfo>[];
    for (final meeting in meetings) {
      final folder = await _getMeetingFolder(meeting);
      if (folder != null && await folder.exists()) {
        final files = await folder.list().where((e) => e is File).toList();
        result.add(MeetingFolderInfo(
          meeting: meeting,
          folderPath: folder.path,
          files: files.map((f) => f.path).toList(),
        ));
      }
    }
    return result;
  }

  // ==================== 搜索 ====================

  Future<List<Meeting>> searchMeetings(String keyword) async {
    if (kIsWeb) {
      final list = _loadMeetingsFromPrefs(await prefs);
      return list.where((m) =>
        (m.title.contains(keyword)) ||
        (m.transcript?.contains(keyword) ?? false) ||
        (m.summary?.contains(keyword) ?? false)
      ).toList();
    }
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'meetings',
      columns: ['id', 'title', 'date', 'participants', 'recordingDuration', 'folderName'],
      where: 'title LIKE ?',
      whereArgs: ['%$keyword%'],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Meeting.fromMap(maps[i]));
  }

  // ==================== 导入导出 ====================

  Future<void> exportMeeting(Meeting meeting, String format, String filePath) async {
    final detail = await loadMeetingDetail(meeting.id!);
    final transcript = detail?.transcript ?? '';
    switch (format) {
      case 'txt':
        await File(filePath).writeAsString(transcript);
        break;
      case 'json':
        await File(filePath).writeAsString(jsonEncode(meeting.toMap()));
        break;
      default:
        throw Exception('Unsupported export format: $format');
    }
  }

  Future<Meeting> importMeeting(String format, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    switch (format) {
      case 'txt':
        final content = await file.readAsString();
        return Meeting(
          title: '导入的会议',
          date: DateTime.now(),
          transcript: content,
          summary: '从TXT文件导入',
          folderName: '',
        );
      case 'json':
        final content = await file.readAsString();
        final map = jsonDecode(content);
        return Meeting.fromMap(map);
      default:
        throw Exception('Unsupported import format: $format');
    }
  }
}

/// 会议文件夹信息（用于云导出）
class MeetingFolderInfo {
  final Meeting meeting;
  final String folderPath;
  final List<String> files;

  MeetingFolderInfo({
    required this.meeting,
    required this.folderPath,
    required this.files,
  });
}
