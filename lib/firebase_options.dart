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
    apiKey: 'AIzaSyDeO15iDL-kJ-FOHcKRApj-vb-i5-rjIv0',
    authDomain: 'fixnow-a6515.firebaseapp.com',
    projectId: 'fixnow-a6515',
    storageBucket: 'fixnow-a6515.firebasestorage.app',
    messagingSenderId: '778888734140',
    appId: '1:778888734140:web:16c0c10ff7ea785f7f37b9',
    measurementId: 'G-H6Z2Y23ZPH',
  );
}
