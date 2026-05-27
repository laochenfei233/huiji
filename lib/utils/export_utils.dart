import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:yanji/models/meeting.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportUtils {
  static Future<void> exportMeeting(Meeting meeting, String format, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    
    switch (format) {
      case 'txt':
        final content = '''
Meeting: ${meeting.title}
Date: ${meeting.date}

Transcript:
${meeting.transcript ?? ''}

Summary:
${meeting.summary ?? ''}
''';
        await file.writeAsString(content);
        break;
        
      case 'json':
        final content = meeting.toMap();
        await file.writeAsString(jsonEncode(content));
        break;
        
      default:
        throw Exception('Unsupported export format: $format');
    }
  }
  
  static Future<void> exportMeetingToPDF(Meeting meeting, String fileName) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Meeting: ${meeting.title}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Date: ${meeting.date}'),
              pw.SizedBox(height: 20),
              pw.Text(
                'Transcript:',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(meeting.transcript ?? ''),
              pw.SizedBox(height: 20),
              pw.Text(
                'Summary:',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(meeting.summary ?? ''),
            ],
          );
        },
      ),
    );
    
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    
    await file.writeAsBytes(await pdf.save());
  }
}