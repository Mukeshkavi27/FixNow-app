import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(firebaseRefsProvider).firestore);
});

class NotificationRepository {
  NotificationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppNotification>> watchUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(AppNotification.fromFirestore).toList();
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return items;
    });
  }

  Stream<List<AppNotification>> watchBranchApprovalNotifications(
    String branchId,
  ) {
    return _firestore
        .collection('notifications')
        .where('branchId', isEqualTo: branchId)
        .where('recipientRole', isEqualTo: 'branchAdmin')
        .where('type', isEqualTo: 'technicianRegistration')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(AppNotification.fromFirestore).toList();
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return items;
    });
  }

  Stream<List<AppNotification>> watchBranchAlerts(String branchId) {
    return _firestore
        .collection('notifications')
        .where('branchId', isEqualTo: branchId)
        .where('recipientRole', isEqualTo: 'branchAdmin')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(AppNotification.fromFirestore).toList();
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return items;
    });
  }

  Future<void> markRead(String notificationId) {
    return _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }
}
