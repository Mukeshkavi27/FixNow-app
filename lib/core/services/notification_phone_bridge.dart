import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/shared/data/notification_repository.dart';
import '../../features/shared/domain/app_notification.dart';
import '../enums/user_role.dart';
import 'notification_popup_service.dart';
import 'push_token_service.dart';

/// Makes the existing Firestore notification feed visible on a phone for every
/// signed-in role. Historical notifications are deliberately ignored by the
/// popup service; only new, unread events interrupt the user.
class NotificationPhoneBridge {
  NotificationPhoneBridge._();

  static final NotificationPhoneBridge instance = NotificationPhoneBridge._();

  StreamSubscription<List<AppNotification>>? _userSubscription;
  StreamSubscription<List<AppNotification>>? _branchSubscription;
  String? _activeUserId;

  Future<void> sync({
    required AppUser? user,
    required FirebaseFirestore firestore,
  }) async {
    if (user?.uid == _activeUserId) return;
    await _userSubscription?.cancel();
    await _branchSubscription?.cancel();
    _userSubscription = null;
    _branchSubscription = null;
    _activeUserId = user?.uid;
    if (user == null) return;

    final notifications = NotificationRepository(firestore);
    _userSubscription = notifications.watchUserNotifications(user.uid).listen(
      _showNotifications,
      onError: (_) {},
    );
    if (user.role == UserRole.branchAdmin &&
        (user.branchId ?? '').trim().isNotEmpty) {
      _branchSubscription =
          notifications.watchBranchAlerts(user.branchId!).listen(
        _showNotifications,
        onError: (_) {},
      );
    }

    // Register every role for device delivery. The tracking server currently
    // uses these tokens for automation alerts and can deliver other workflow
    // notifications without a role-specific device setup.
    await PushTokenService.instance.registerUser(
      userId: user.uid,
      role: user.role.name,
      branchId: user.branchId,
      firestore: firestore,
    );
  }

  void _showNotifications(List<AppNotification> notifications) {
    for (final notification in notifications) {
      unawaited(NotificationPopupService.instance.showNewUnread(notification));
    }
  }
}
