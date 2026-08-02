import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnow/core/errors/user_facing_error.dart';

void main() {
  group('userFacingAuthError', () {
    test('maps invalid Firebase credentials to a safe message', () {
      final message = userFacingAuthError(
        FirebaseAuthException(code: 'invalid-credential'),
      );

      expect(
        message,
        'Invalid credentials. Check your email and password.',
      );
      expect(message.toLowerCase(), isNot(contains('firebase')));
    });

    test('does not expose Firestore permission error codes', () {
      final message = userFacingAuthError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );

      expect(message,
          'This account does not have access. Contact FixNow support.');
      expect(message.toLowerCase(), isNot(contains('permission-denied')));
      expect(message.toLowerCase(), isNot(contains('firestore')));
    });

    test('maps network and timeout failures', () {
      expect(
        userFacingAuthError(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        'Unable to connect. Check your internet and try again.',
      );
      expect(
        userFacingAuthError(TimeoutException('internal timeout')),
        'The service is taking too long. Check your connection and try again.',
      );
    });

    test('preserves safe business messages but hides internal state errors',
        () {
      expect(
        userFacingAuthError(StateError('Your account is pending approval.')),
        'Your account is pending approval.',
      );
      expect(
        userFacingAuthError(StateError('Firestore permission-denied')),
        'Unable to sign in right now. Please try again.',
      );
    });
  });
}
