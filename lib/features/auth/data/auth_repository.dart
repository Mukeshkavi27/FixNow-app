import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required String phone,
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
      createdAt: DateTime.now(),
      isActive: true,
    );
    try {
      await _firestore.collection('users').doc(uid).set(user.toJson());
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
  }) async {
    final changes = <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (profilePhoto != null) changes['profilePhoto'] = profilePhoto;
    await _firestore.collection('users').doc(uid).update(changes);
    await _auth.currentUser?.updateDisplayName(name.trim());
    if (profilePhoto != null) {
      await _auth.currentUser?.updatePhotoURL(profilePhoto);
    }
  }

  Future<void> sendPasswordReset() async {
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('No email is linked to this account.');
    }
    await _auth.sendPasswordResetEmail(email: email);
  }
}
