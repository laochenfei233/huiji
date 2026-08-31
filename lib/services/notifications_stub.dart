class FlutterLocalNotificationsPlugin {
  Future<void> initialize(dynamic settings) async {}
  Future<void> show(int id, String? title, String? body, dynamic details) async {}
  Future<void> cancel(int id) async {}
  T? resolvePlatformSpecificImplementation<T>() => null;
}

class AndroidInitializationSettings {
  const AndroidInitializationSettings(String icon);
}

class DarwinInitializationSettings {
  const DarwinInitializationSettings({
    bool requestAlertPermission = true,
    bool requestBadgePermission = true,
    bool requestSoundPermission = true,
  });
}

class InitializationSettings {
  const InitializationSettings({dynamic android, dynamic iOS});
}

class AndroidNotificationChannel {
  const AndroidNotificationChannel(String id, String name, {String? description, dynamic importance, bool playSound = true, bool enableVibration = true});
}

class AndroidNotificationDetails {
  const AndroidNotificationDetails(String channelId, String channelName, {String? channelDescription, dynamic importance, dynamic priority, bool ongoing = false, bool autoCancel = true, String? icon, dynamic color, dynamic visibility, dynamic styleInformation});
}

class DarwinNotificationDetails {
  const DarwinNotificationDetails({bool presentAlert = true, bool presentBadge = true, bool presentSound = true});
}

class NotificationDetails {
  const NotificationDetails({dynamic android, dynamic iOS});
}

class BigTextStyleInformation {
  const BigTextStyleInformation(String text, {String? contentTitle, String? summaryText});
}

class AndroidFlutterLocalNotificationsPlugin {
  Future<void> createNotificationChannel(dynamic channel) async {}
}

enum Importance { defaultImportance, max, min, low, high, none, unspecified }
enum Priority { defaultPriority, max, min, low, high }
enum NotificationVisibility { public, private, secret }
