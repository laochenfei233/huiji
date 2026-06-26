import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yanji/models/meeting.dart';

/// 数据迁移服务
/// 将旧数据库中的 transcript/summary 数据迁移到文件存储
class DataMigrationService {
  static bool _migrationCompleted = false;

  /// 检查并执行数据迁移
  static Future<void> checkAndMigrate() async {
    if (kIsWeb || _migrationCompleted) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = join(directory.path, 'meetings.db');

      if (!await File(dbPath).exists()) return;

      final db = await openDatabase(dbPath, readOnly: true);

      // 检查表结构
      final columns = await db.rawQuery('PRAGMA table_info(meetings)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      debugPrint('[Migration] 当前列: $columnNames');

      final hasTranscript = columnNames.contains('transcript');
      final hasSummary = columnNames.contains('summary');
      final hasAudioBase64 = columnNames.contains('audioBase64');

      if (!hasTranscript && !hasSummary && !hasAudioBase64) {
        await db.close();
        _migrationCompleted = true;
        return;
      }

      debugPrint('[Migration] 检测到旧数据格式，开始迁移...');

      // 逐条迁移，避免 CursorWindow 溢出
      int offset = 0;
      const batchSize = 10;
      bool hasMore = true;

      while (hasMore) {
        // 只查询需要的列
        final queryColumns = ['id', 'title'];
        if (hasTranscript) queryColumns.add('transcript');
        if (hasSummary) queryColumns.add('summary');

        final rows = await db.query(
          'meetings',
          columns: queryColumns,
          limit: batchSize,
          offset: offset,
        );

        if (rows.isEmpty) {
          hasMore = false;
          break;
        }

        for (final row in rows) {
          await _migrateRow(row, hasTranscript, hasSummary);
        }

        offset += batchSize;
      }

      await db.close();
      debugPrint('[Migration] 数据迁移完成');
      _migrationCompleted = true;
    } catch (e) {
      debugPrint('[Migration] 迁移失败: $e');
    }
  }

  /// 迁移单行数据
  static Future<void> _migrateRow(
    Map<String, dynamic> row,
    bool hasTranscript,
    bool hasSummary,
  ) async {
    final id = row['id'] as int;
    final title = row['title'] as String? ?? '';
    final transcript = hasTranscript ? (row['transcript'] as String? ?? '') : '';
    final summary = hasSummary ? (row['summary'] as String? ?? '') : '';

    if (transcript.isEmpty && summary.isEmpty) return;

    final meetingsRoot = await _getMeetingsRoot();
    final folderName = Meeting.generateFolderName(id, title);
    final folder = Directory(join(meetingsRoot.path, folderName));

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    // 写入 transcript.md
    if (transcript.isNotEmpty) {
      final file = File(join(folder.path, 'transcript.md'));
      if (!await file.exists()) {
        await file.writeAsString(transcript);
        debugPrint('[Migration] 迁移会议 $id 的转录文本 (${transcript.length} 字符)');
      }
    }

    // 写入 summary.md
    if (summary.isNotEmpty) {
      final file = File(join(folder.path, 'summary.md'));
      if (!await file.exists()) {
        await file.writeAsString(summary);
        debugPrint('[Migration] 迁移会议 $id 的摘要文本 (${summary.length} 字符)');
      }
    }
  }

  /// 删除旧列（SQLite 不支持 DROP COLUMN，需要重建表）
  static Future<void> _dropOldColumns() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = join(directory.path, 'meetings.db');

      final db = await openDatabase(dbPath);

      // 检查是否有旧列
      final columns = await db.rawQuery('PRAGMA table_info(meetings)');
      final hasTranscript = columns.any((c) => c['name'] == 'transcript');
      final hasSummary = columns.any((c) => c['name'] == 'summary');

      if (!hasTranscript && !hasSummary) {
        await db.close();
        return;
      }

      debugPrint('[Migration] 清理旧列...');

      // 重建表（保留新结构的列）
      await db.transaction((txn) async {
        // 创建新表
        await txn.execute('''
          CREATE TABLE meetings_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            date TEXT,
            folderName TEXT,
            participants TEXT,
            recordingDuration INTEGER DEFAULT 0
          )
        ''');

        // 复制数据
        await txn.execute('''
          INSERT INTO meetings_new (id, title, date, folderName, participants, recordingDuration)
          SELECT id, title, date, folderName, participants, recordingDuration FROM meetings
        ''');

        // 删除旧表
        await txn.execute('DROP TABLE meetings');

        // 重命名新表
        await txn.execute('ALTER TABLE meetings_new RENAME TO meetings');
      });

      await db.close();
      debugPrint('[Migration] 旧列清理完成');
    } catch (e) {
      debugPrint('[Migration] 清理旧列失败: $e');
    }
  }

  static Future<Directory> _getMeetingsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(join(docs.path, 'meetings'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }
}
