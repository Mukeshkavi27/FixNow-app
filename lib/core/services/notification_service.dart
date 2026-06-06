import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService(this._messaging);

  final FirebaseMessaging _messaging;

  Future<String?> registerDevice() async {
    await _messaging.requestPermission();
    return _messaging.getToken();
  }

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;
}
