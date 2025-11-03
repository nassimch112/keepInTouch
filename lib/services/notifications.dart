import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/db.dart';

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(NotificationResponse response)? onResponse;
  static void Function(NotificationResponse response)? onBackgroundResponse;

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (r) => onResponse?.call(r),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const androidNudges = AndroidNotificationChannel(
      'nudges', 'Nudges',
      description: 'Per-person reminders', importance: Importance.defaultImportance,
    );
    const androidBatch = AndroidNotificationChannel(
      'batch', 'Batch',
      description: 'Weekly batch reminders', importance: Importance.defaultImportance,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(androidNudges);
    await android?.createNotificationChannel(androidBatch);
  }

  static Future<void> showImmediate({required String title, required String body, String channelId = 'nudges', String? payload}) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(channelId, channelId, importance: Importance.defaultImportance),
    );
    await _plugin.show(DateTime.now().millisecondsSinceEpoch % 100000, title, body, details, payload: payload);
  }

  static Future<void> showPersonNudge({required int personId, required String name}) async {
    final androidDetails = AndroidNotificationDetails(
      'nudges', 'Nudges',
      importance: Importance.defaultImportance,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('done_$personId', 'Done', showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction('snooze_$personId', 'Snooze', showsUserInterface: true),
      ],
    );
    await _plugin.show(
      personId % 100000 + 10000,
      'Reach out',
      name,
      NotificationDetails(android: androidDetails),
      payload: 'person:$personId',
    );
  }

  static Future<void> showSummary(int count) async {
    final details = AndroidNotificationDetails('batch', 'Batch', importance: Importance.defaultImportance);
    await _plugin.show(7777, 'KeepInTouch', '$count to reach out today', NotificationDetails(android: details), payload: 'open:batch');
  }

  // Helper to extract a person id from a notification response
  static int? extractPersonId(NotificationResponse r) {
    final a = r.actionId;
    if ((a?.startsWith('done_') ?? false) || (a?.startsWith('snooze_') ?? false)) {
      final parts = a!.split('_');
      if (parts.length == 2) return int.tryParse(parts[1]);
    }
    if (r.payload != null && r.payload!.startsWith('person:')) {
      return int.tryParse(r.payload!.substring('person:'.length));
    }
    return null;
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  // Background response handler: handle 'done_<id>' quickly
  final id = Notifier.extractPersonId(response);
  if (id != null && (response.actionId?.startsWith('done_') ?? false)) {
    final db = await AppDb.instance;
    await PersonRepo(db).markDone(id, initiator: 'me');
  }
  // snooze requires UI; app will handle when it comes to foreground
}

