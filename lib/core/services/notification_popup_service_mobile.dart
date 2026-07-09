import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/shared/domain/app_notification.dart';

class NotificationPopupService {
  NotificationPopupService._();

  static final NotificationPopupService instance = NotificationPopupService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Set<String> _shownNotificationIds = <String>{};
  final DateTime _startedAt = DateTime.now();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _plugin.initialize(settings: initializationSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> showNewUnread(AppNotification notification) async {
    if (notification.isRead ||
        _shownNotificationIds.contains(notification.id) ||
        notification.createdAt.isBefore(
          _startedAt.subtract(const Duration(seconds: 5)),
        )) {
      return;
    }
    await initialize();
    if (!_initialized) return;
    _shownNotificationIds.add(notification.id);
    await showPopup(
      id: notification.id.hashCode,
      title: notification.title,
      body: notification.body,
      payload: notification.bookingId,
    );
  }

  Future<void> showPopup({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    if (!_initialized) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'fixnow_technician_alerts',
          'Technician alerts',
          channelDescription: 'Job assignments and urgent technician updates',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }
}
