import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('Run flutterfire configure for iOS options.');
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDeO15iDL-kJ-FOHcKRApj-vb-i5-rjIv0',
    authDomain: 'fixnow-a6515.firebaseapp.com',
    projectId: 'fixnow-a6515',
    storageBucket: 'fixnow-a6515.firebasestorage.app',
    messagingSenderId: '778888734140',
    appId: '1:778888734140:web:16c0c10ff7ea785f7f37b9',
    measurementId: 'G-H6Z2Y23ZPH',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIXNOW_FIREBASE_API_KEY',
      defaultValue: 'AIzaSyA7xUQmSccYmUO4EtdZLga2Z7kgwKbzsR0',
    ),
    authDomain: String.fromEnvironment(
      'FIXNOW_FIREBASE_AUTH_DOMAIN',
      defaultValue: 'fixnow-a6515.firebaseapp.com',
    ),
    projectId: String.fromEnvironment(
      'FIXNOW_FIREBASE_PROJECT_ID',
      defaultValue: 'fixnow-a6515',
    ),
    storageBucket: String.fromEnvironment(
      'FIXNOW_FIREBASE_STORAGE_BUCKET',
      defaultValue: 'fixnow-a6515.firebasestorage.app',
    ),
    messagingSenderId: String.fromEnvironment(
      'FIXNOW_FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '778888734140',
    ),
    appId: String.fromEnvironment(
      'FIXNOW_FIREBASE_APP_ID',
      defaultValue: '1:778888734140:android:61108790109487cc7f37b9',
    ),
    measurementId: 'G-H6Z2Y23ZPH',
  );
}
