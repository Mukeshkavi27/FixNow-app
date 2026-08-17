import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/app_user.dart';

const _configuredMobileAuthApiUrl = String.fromEnvironment(
  'FIXNOW_AUTH_API_URL',
  defaultValue: '',
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseRefsProvider).auth,
      ref.watch(firebaseRefsProvider).firestore);
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authUser = ref.watch(authStateProvider).valueOrNull;
  if (authUser == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchUser(authUser.uid);
});

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Stream<AppUser?> watchUser(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Future<void> signIn(String email, String password) async {
    final credential = await _auth
        .signInWithEmailAndPassword(
          email: email,
          password: password,
        )
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw StateError(
            'Sign-in is taking too long. Check your connection and try again.',
          ),
        );
    await _validateSignedInUser(credential);
  }

  Future<void> signInWithMobilePassword({
    required String phone,
    required String password,
    required String role,
  }) async {
    final baseUrl = _configuredMobileAuthApiUrl.isNotEmpty
        ? _configuredMobileAuthApiUrl
        : kDebugMode
            ? 'http://127.0.0.1:8088'
            : '';
    if (baseUrl.isEmpty) {
      throw StateError('Mobile login is not configured for this app.');
    }
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(
                '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/auth/mobile-password'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'password': password,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw StateError(
        'Mobile login server is not responding. Start the FixNow tracking server and try again.',
      );
    } on http.ClientException {
      throw StateError(
        'Mobile login server is offline. Start npm in tracking-server and keep that terminal open.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['ok'] != true) {
      throw StateError(body['error'] as String? ?? 'Invalid mobile number or password');
    }
    final token = body['customToken'] as String?;
    if (token == null || token.isEmpty) throw StateError('Mobile login failed.');
    final credential = await _auth.signInWithCustomToken(token);
    await _validateSignedInUser(credential);
  }

  Future<void> _validateSignedInUser(UserCredential credential) async {
    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError('Unable to sign in right now. Please try again.');
    }
    final profile = await _firestore.collection('users').doc(uid).get().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw StateError(
            'Your account profile is taking too long to load. Please try again.',
          ),
        );
    if (!profile.exists) {
      await signOut();
      throw StateError(
        'Account profile not found for this login. Please contact FixNow admin.',
      );
    }
    final appUser = AppUser.fromFirestore(profile);
    final denial = appUser.accessDenialReason;
    if (denial != null) {
      await signOut();
      throw StateError(denial);
    }
  }

  String _normalizeIndianPhone(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.length == 10) return '+91$digits';
    if (digits.startsWith('91') && digits.length == 12) return '+$digits';
    throw ArgumentError('Enter a valid Indian mobile number.');
  }

  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required String phone,
    String? branchId,
    String? branchName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    final uid = credential.user!.uid;
    final user = AppUser(
      uid: uid,
      name: name,
      email: email,
      phone: phone,
      role: UserRole.customer,
      accountStatus: AccountStatus.approved,
      createdAt: DateTime.now(),
      isActive: true,
      branchId: branchId,
      branchName: branchName,
    );
    try {
      final data = user.toJson()
        ..['phoneNormalized'] = _normalizeIndianPhone(phone);
      await _firestore.collection('users').doc(uid).set(data);
    } catch (_) {
      await credential.user?.delete();
      rethrow;
    }
  }

  Future<void> createTechnicianRequest({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String branchId,
    required String branchName,
    double? requestLatitude,
    double? requestLongitude,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;
    final user = AppUser(
      uid: uid,
      name: name,
      email: email,
      phone: phone,
      role: UserRole.technician,
      accountStatus: AccountStatus.pendingApproval,
      createdAt: DateTime.now(),
      isActive: false,
      branchId: branchId,
      branchName: branchName,
      requestLatitude: requestLatitude,
      requestLongitude: requestLongitude,
    );
    try {
      final batch = _firestore.batch();
      final data = user.toJson()
        ..['phoneNormalized'] = _normalizeIndianPhone(phone);
      batch.set(_firestore.collection('users').doc(uid), data);
      batch.set(
          _firestore
              .collection('notifications')
              .doc('technician_registration_$uid'),
          {
            'userId': 'branch:$branchId',
            'recipientRole': UserRole.branchAdmin.name,
            'technicianId': uid,
            'branchId': branchId,
            'type': 'technicianRegistration',
            'title': 'Technician approval requested',
            'body': '$name requested technician access for $branchName.',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await batch.commit();
    } catch (_) {
      await credential.user?.delete();
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> updateCustomerProfile({
    required String uid,
    required String name,
    required String phone,
    String? profilePhoto,
    String? branchId,
    String? branchName,
  }) async {
    final changes = <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'phoneNormalized': _normalizeIndianPhone(phone),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (profilePhoto != null) changes['profilePhoto'] = profilePhoto;
    if (branchId != null) changes['branchId'] = branchId;
    if (branchName != null) changes['branchName'] = branchName;
    await _firestore.collection('users').doc(uid).update(changes);
    await _auth.currentUser?.updateDisplayName(name.trim());
    if (profilePhoto != null) {
      await _auth.currentUser?.updatePhotoURL(profilePhoto);
    }
  }

  Future<void> updateUserBranch({
    required String uid,
    required String branchId,
    required String branchName,
  }) {
    return _firestore.collection('users').doc(uid).update({
      'branchId': branchId,
      'branchName': branchName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateLastServiceLocation({
    required String uid,
    required String address,
    double? latitude,
    double? longitude,
  }) {
    return _firestore.collection('users').doc(uid).update({
      'lastServiceAddress': address.trim(),
      'lastServiceLatitude': latitude,
      'lastServiceLongitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateFaceReference({
    required String uid,
    required String photoUrl,
    required String signature,
  }) {
    return _firestore.collection('users').doc(uid).update({
      'faceReferencePhoto': photoUrl,
      'faceReferenceSignature': signature,
      'faceReferenceUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendPasswordReset() async {
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('No email is linked to this account.');
    }
    await _auth.sendPasswordResetEmail(email: email);
  }
}
