import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  static void _onNotificationTapped(NotificationResponse response) async {
    // When notification is tapped, copy the cleaned URL back to clipboard
    if (response.payload != null && response.payload!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: response.payload!));
    }
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    bool isSuccess = true,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'link_pure_channel',
      'LinkPure Notifications',
      channelDescription: 'Notifications for URL cleaning',
      importance: Importance.high,
      priority: Priority.high,
      timeoutAfter: 5000, // Auto-dismiss after 5 seconds
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notifications.show(
      0,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
