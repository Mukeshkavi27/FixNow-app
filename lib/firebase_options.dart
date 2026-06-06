import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Run flutterfire configure to add web options.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError('Run flutterfire configure to add Android options.');
      case TargetPlatform.iOS:
        throw UnsupportedError('Run flutterfire configure to add iOS options.');
      case TargetPlatform.macOS:
        throw UnsupportedError('Run flutterfire configure to add macOS options.');
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError('FixNow supports Android and iOS production targets.');
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }
}
