import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_popup_service.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  bool _foregroundListenerAttached = false;
  final Set<String> _registeredUsers = <String>{};

  Future<void> registerUser({
    required String userId,
    required String role,
    String? branchId,
    required FirebaseFirestore firestore,
  }) async {
    if (_registeredUsers.contains(userId)) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _saveToken(
      firestore: firestore,
      userId: userId,
      role: role,
      branchId: branchId,
      token: token,
    );
    _registeredUsers.add(userId);
    messaging.onTokenRefresh.listen((newToken) {
      _saveToken(
        firestore: firestore,
        userId: userId,
        role: role,
        branchId: branchId,
        token: newToken,
      );
    });
    _attachForegroundListener();
  }

  Future<void> _saveToken({
    required FirebaseFirestore firestore,
    required String userId,
    required String role,
    String? branchId,
    required String token,
  }) {
    return firestore.collection('device_tokens').doc(userId).set({
      'userId': userId,
      'token': token,
      'platform': defaultTargetPlatform.name,
      'role': role,
      'branchId': branchId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> registerTechnician({
    required String userId,
    required FirebaseFirestore firestore,
  }) => registerUser(
        userId: userId,
        role: 'technician',
        branchId: null,
        firestore: firestore,
      );

  void _attachForegroundListener() {
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? message.data['title'];
      final body = message.notification?.body ?? message.data['body'];
      if (title == null || body == null) return;
      NotificationPopupService.instance.showPopup(
        id: message.messageId.hashCode,
        title: title,
        body: body,
        payload: message.data['bookingId'],
      );
    });
  }
}
