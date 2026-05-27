import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class LogoFinal extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF5BA3E6),
          const Color(0xFF3A7BC8),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.22)),
      bgPaint,
    );

    final bars = [0.30, 0.50, 0.72, 0.90, 0.72, 0.50, 0.30];
    final barW = w * 0.052;
    final gap = w * 0.032;
    final totalW = 7 * barW + 6 * gap;
    final startX = (w - totalW) / 2;
    final centerY = h * 0.50;
    final maxBarH = h * 0.46;

    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 7; i++) {
      final x = startX + i * (barW + gap) + barW / 2;
      final halfH = maxBarH * bars[i] / 2;
      paint.strokeWidth = barW;
      canvas.drawLine(
        Offset(x, centerY - halfH),
        Offset(x, centerY + halfH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  test('generate all icon sizes', () async {
    final sizes = {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };

    final resDir = Directory('android/app/src/main/res');

    for (final entry in sizes.entries) {
      final size = entry.value;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      LogoFinal().paint(canvas, Size(size.toDouble(), size.toDouble()));
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = Directory('${resDir.path}/${entry.key}');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/ic_launcher.png').writeAsBytes(bytes);
      print('✓ ${entry.key}: ${size}x${size}');
    }

    // 512px 预览
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2);
    LogoFinal().paint(c2, const Size(512, 512));
    final p2 = r2.endRecording();
    final img2 = await p2.toImage(512, 512);
    final bd2 = await img2.toByteData(format: ui.ImageByteFormat.png);
    await File('assets/logo.png').writeAsBytes(bd2!.buffer.asUint8List());
    print('✓ assets/logo.png');

    // 删除临时文件
    final tempFiles = [
      'assets/logo.svg',
      'assets/logo_a_wave.png',
      'assets/logo_a_v2.png',
      'assets/logo_a_v3.png',
      'assets/logo_a_v4.png',
      'assets/logo_b_doc.png',
      'assets/logo_c_mic.png',
      'assets/logo_final.png',
    ];
    for (final f in tempFiles) {
      final file = File(f);
      if (await file.exists()) {
        await file.delete();
        print('✗ deleted $f');
      }
    }
  });
}
