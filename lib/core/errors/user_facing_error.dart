import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

enum AuthAction { signIn, createAccount }

String userFacingOperationError(Object error) {
  if (error is TimeoutException) {
    return 'The request took too long. Check your connection and try again.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'Your session cannot perform this action. Sign in again and retry.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The service is temporarily unavailable. Please try again.';
    }
  }
  if (error is StateError) {
    final message = error.message.toString().trim();
    if (message.isNotEmpty && !_looksLikeInternalError(message)) return message;
  }
  return 'Unable to complete this action. Please try again.';
}

String userFacingAuthError(
  Object error, {
  AuthAction action = AuthAction.signIn,
}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid credentials. Check your email and password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account is disabled. Contact FixNow support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Unable to connect. Check your internet and try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Choose a stronger password and try again.';
      case 'operation-not-allowed':
        return 'Mobile OTP is not enabled yet. In Firebase Console, enable Phone under Authentication > Sign-in method.';
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'Enter a valid 10-digit Indian mobile number.';
      case 'captcha-check-failed':
      case 'web-context-canceled':
        return 'Phone verification could not complete. Allow the verification popup and try again.';
      case 'app-not-authorized':
      case 'invalid-app-credential':
        return 'This app is not authorised for mobile OTP. Add its Android SHA-1 and SHA-256 fingerprints in Firebase, then rebuild the app.';
      case 'quota-exceeded':
        return 'OTP sending limit has been reached. Wait before requesting another code.';
      case 'invalid-verification-code':
        return 'That OTP is incorrect. Check the latest SMS and try again.';
      case 'session-expired':
        return 'This OTP has expired. Request a new one.';
    }
  }

  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return action == AuthAction.signIn
            ? 'This account does not have access. Contact FixNow support.'
            : 'You do not have permission to create this account.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The service is temporarily unavailable. Please try again.';
    }
  }

  if (error is TimeoutException) {
    return 'The service is taking too long. Check your connection and try again.';
  }

  // Repository StateErrors contain deliberately written, user-safe business
  // messages (for example, pending approval or a missing account profile).
  if (error is StateError) {
    final message = error.message.toString().trim();
    if (message.isNotEmpty && !_looksLikeInternalError(message)) {
      return message;
    }
  }

  return action == AuthAction.signIn
      ? 'Unable to sign in right now. Please try again.'
      : 'Unable to create the account right now. Please try again.';
}

bool _looksLikeInternalError(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('firebase') ||
      normalized.contains('firestore') ||
      normalized.contains('permission-denied') ||
      normalized.contains('cloud_firestore') ||
      normalized.contains('firebase_auth') ||
      normalized.contains('exception:');
}
