import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/app_user.dart';

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
            'Firebase Auth did not respond. Check internet, Firebase project, and web app config.',
          ),
        );
    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError('Unable to sign in right now. Please try again.');
    }
    final profile = await _firestore.collection('users').doc(uid).get().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw StateError(
            'Signed in, but Firestore profile did not load. Check Firestore rules and network.',
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
      await _firestore.collection('users').doc(uid).set(user.toJson());
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
      batch.set(_firestore.collection('users').doc(uid), user.toJson());
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
