import 'dart:async';
import 'package:yanji/services/notifications_adapter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 录音常驻通知服务
/// 简洁风格，显示录音状态和最新转录文字
class RecordingNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _notificationId = 1001;
  static bool _enabled = true;

  /// 初始化通知服务
  static Future<void> init() async {
    if (_initialized) return;

    // 读取用户设置
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('recording_notification') ?? true;

    if (!_enabled) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initSettings);
    await _createNotificationChannel();
    _initialized = true;
  }

  static Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'recording_channel',
      '录音状态',
      description: '显示当前录音状态',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 刷新用户设置
  static Future<void> refreshSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('recording_notification') ?? true;
  }

  /// 显示录音通知
  static Future<void> showRecordingNotification({
    required bool isPaused,
    required int duration,
    required String transcript,
  }) async {
    if (!_enabled) return;
    if (!_initialized) await init();
    if (!_initialized) return;

    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    String displayText = transcript;
    if (displayText.length > 10) {
      displayText = '...${displayText.substring(displayText.length - 10)}';
    }
    if (displayText.isEmpty) {
      displayText = '正在录音...';
    }

    final androidDetails = AndroidNotificationDetails(
      'recording_channel',
      '录音状态',
      channelDescription: '显示当前录音状态',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF4A90D9),
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        displayText,
        contentTitle: timeStr,
        summaryText: isPaused ? '已暂停' : '录音中',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    await _plugin.show(
      id: _notificationId,
      title: timeStr,
      body: '${isPaused ? '已暂停' : '录音中'}  |  $displayText',
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// 取消录音通知
  static Future<void> cancelRecordingNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _notificationId);
  }
}
