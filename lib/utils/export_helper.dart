import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportHelper {
  /// 复制文本到剪贴板
  static Future<void> copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  /// 导出 Markdown 文件
  static Future<void> exportMarkdown(
    BuildContext context, {
    required String title,
    required String summary,
    String? transcript,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('# $title\n');
    buffer.writeln(summary);
    if (transcript != null && transcript.isNotEmpty) {
      buffer.writeln('\n---\n');
      buffer.writeln('## 会议原文\n');
      buffer.writeln(transcript);
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeName = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName.md');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles([XFile(file.path)], text: '会议纪要: $title');
  }

  /// 导出 Word 文档（HTML 格式，Word 可直接打开）
  static Future<void> exportWord(
    BuildContext context, {
    required String title,
    required String summary,
    String? transcript,
  }) async {
    final html = _buildHtml(title, summary, transcript);

    final dir = await getApplicationDocumentsDirectory();
    final safeName = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName.doc');
    await file.writeAsString(html);

    await Share.shareXFiles([XFile(file.path)], text: '会议纪要: $title');
  }

  static String _buildHtml(String title, String summary, String? transcript) {
    final summaryHtml = _markdownToHtml(summary);
    final transcriptHtml = transcript != null && transcript.isNotEmpty
        ? '''
<h2>会议原文</h2>
<div style="background:#f5f5f5;padding:16px;border-radius:8px;font-size:13px;line-height:1.8;white-space:pre-wrap;">${_escapeHtml(transcript)}</div>
'''
        : '';

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
  body { font-family: "Microsoft YaHei", "SimSun", Arial, sans-serif; padding: 40px; line-height: 1.8; color: #333; }
  h1 { color: #1a1a1a; border-bottom: 2px solid #333; padding-bottom: 8px; }
  h2 { color: #2c3e50; margin-top: 24px; }
  h3 { color: #34495e; }
  strong { color: #1a1a1a; }
  ul, ol { padding-left: 24px; }
  li { margin-bottom: 4px; }
  blockquote { border-left: 3px solid #ccc; padding-left: 12px; color: #666; margin: 12px 0; }
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
  th { background: #f5f5f5; }
</style>
</head>
<body>
<h1>$title</h1>
$summaryHtml
$transcriptHtml
</body>
</html>
''';
  }

  /// 简易 Markdown → HTML 转换
  static String _markdownToHtml(String md) {
    var html = _escapeHtml(md);

    // 标题
    html = html.replaceAllMapped(RegExp(r'^### (.+)$', multiLine: true),
        (m) => '<h3>${m.group(1)}</h3>');
    html = html.replaceAllMapped(RegExp(r'^## (.+)$', multiLine: true),
        (m) => '<h2>${m.group(1)}</h2>');
    html = html.replaceAllMapped(RegExp(r'^# (.+)$', multiLine: true),
        (m) => '<h1>${m.group(1)}</h1>');

    // 粗体和斜体
    html = html.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'),
        (m) => '<strong>${m.group(1)}</strong>');
    html = html.replaceAllMapped(RegExp(r'\*(.+?)\*'),
        (m) => '<em>${m.group(1)}</em>');

    // 行内代码
    html = html.replaceAllMapped(RegExp(r'`(.+?)`'),
        (m) => '<code>${m.group(1)}</code>');

    // 无序列表
    html = html.replaceAllMapped(
      RegExp(r'^- (.+)$', multiLine: true),
      (m) => '<li>${m.group(1)}</li>',
    );
    html = html.replaceAllMapped(
      RegExp(r'(<li>.*</li>\n?)+', multiLine: true),
      (m) => '<ul>${m.group(0)}</ul>',
    );

    // 引用
    html = html.replaceAllMapped(RegExp(r'^&gt; (.+)$', multiLine: true),
        (m) => '<blockquote>${m.group(1)}</blockquote>');

    // 分割线
    html = html.replaceAll('---', '<hr>');

    // 段落（连续换行变 <br>）
    html = html.replaceAll('\n\n', '</p><p>');
    html = '<p>$html</p>';
    html = html.replaceAll('<p></p>', '');

    return html;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// 显示导出选项菜单
  static Future<void> showExportMenu(
    BuildContext context, {
    required String title,
    required String summary,
    String? transcript,
  }) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '导出会议纪要',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制到剪贴板'),
              onTap: () {
                Navigator.pop(ctx);
                copyToClipboard(context, summary);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('导出 Markdown (.md)'),
              onTap: () {
                Navigator.pop(ctx);
                exportMarkdown(context, title: title, summary: summary, transcript: transcript);
              },
            ),
            ListTile(
              leading: const Icon(Icons.article),
              title: const Text('导出 Word (.doc)'),
              onTap: () {
                Navigator.pop(ctx);
                exportWord(context, title: title, summary: summary, transcript: transcript);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
