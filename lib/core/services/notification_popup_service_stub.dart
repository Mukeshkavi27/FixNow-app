import '../../features/shared/domain/app_notification.dart';

class NotificationPopupService {
  NotificationPopupService._();

  static final NotificationPopupService instance = NotificationPopupService._();

  Future<void> initialize() async {}

  Future<void> showNewUnread(AppNotification notification) async {}

  Future<void> showPopup({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
}
