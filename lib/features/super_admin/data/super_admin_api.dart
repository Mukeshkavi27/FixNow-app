import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

const _configuredAdminApiUrl = String.fromEnvironment(
  'FIXNOW_ADMIN_API_URL',
  defaultValue: '',
);
const _productionAdminApiUrl = 'https://fixnow-tracking-server.onrender.com';
String get _adminApiUrl => AppEnvironment.requireServiceUrl(
      _configuredAdminApiUrl != ''
          ? _configuredAdminApiUrl
          : const bool.fromEnvironment('dart.vm.product')
              ? _productionAdminApiUrl
              : '',
      name: 'FIXNOW_ADMIN_API_URL',
    );

final superAdminApiProvider = Provider<SuperAdminApi>((ref) {
  return SuperAdminApi(
    auth: ref.watch(firebaseRefsProvider).auth,
    firestore: ref.watch(firebaseRefsProvider).firestore,
    client: http.Client(),
  );
});

class SuperAdminApi {
  SuperAdminApi({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required http.Client client,
    String? baseUrl,
    bool? useClientFallback,
  })  : _auth = auth,
        _firestore = firestore,
        _client = client,
        _baseUrl = (baseUrl ?? _adminApiUrl).replaceFirst(RegExp(r'/$'), ''),
        _useClientFallback = useClientFallback ??
            (baseUrl == null &&
                _configuredAdminApiUrl.isEmpty &&
                AppEnvironment.isDevelopment);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final http.Client _client;
  final String _baseUrl;
  final bool _useClientFallback;

  Future<String> createBranchAdmin({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String branchId,
  }) async {
    if (_useClientFallback) {
      return _createBranchAdminWithClientFallback(
        name: name,
        email: email,
        phone: phone,
        password: password,
        branchId: branchId,
      );
    }
    final body = {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      'branchId': branchId,
    };
    try {
      final response =
          await _send('POST', '/api/admin/branch-admins', body: body);
      return response['uid'] as String? ?? '';
    } on StateError catch (error) {
      if (!_isMissingFirebaseAdminCredentials(error)) rethrow;
      return _createBranchAdminWithClientFallback(
        name: name,
        email: email,
        phone: phone,
        password: password,
        branchId: branchId,
      );
    }
  }

  Future<String> createPasswordResetLink(String uid) async {
    if (_useClientFallback) {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      final email = snapshot.data()?['email'] as String?;
      if (email == null || email.trim().isEmpty) {
        throw StateError('Branch Admin email address was not found.');
      }
      await _auth.sendPasswordResetEmail(email: email.trim());
      return '';
    }
    final response = await _send(
      'POST',
      '/api/admin/branch-admins/$uid/password-reset',
    );
    return response['resetLink'] as String? ?? '';
  }

  Future<void> setBranchAdminActive({
    required String uid,
    required bool isActive,
  }) {
    if (_useClientFallback) {
      return _setBranchAdminActiveWithClientFallback(
        uid: uid,
        isActive: isActive,
      );
    }
    return _send(
      'PATCH',
      '/api/admin/branch-admins/$uid/status',
      body: {'isActive': isActive},
    );
  }

  Future<void> transferBranchAdmin({
    required String uid,
    required String branchId,
  }) {
    if (_useClientFallback) {
      return _transferBranchAdminWithClientFallback(
        uid: uid,
        branchId: branchId,
      );
    }
    return _send(
      'PATCH',
      '/api/admin/branch-admins/$uid/branch',
      body: {'branchId': branchId},
    );
  }

  Future<void> transferTechnician({
    required String uid,
    required String branchId,
    required bool futureRevenueStaysWithPreviousBranch,
  }) {
    if (_useClientFallback) {
      return _transferTechnicianWithClientFallback(
        uid: uid,
        branchId: branchId,
        futureRevenueStaysWithPreviousBranch:
            futureRevenueStaysWithPreviousBranch,
      );
    }
    return _send(
      'PATCH',
      '/api/admin/technicians/$uid/branch',
      body: {
        'branchId': branchId,
        'futureRevenueStaysWithPreviousBranch':
            futureRevenueStaysWithPreviousBranch,
      },
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_baseUrl.isEmpty) {
      throw StateError(
        'The FixNow administration service is not configured. '
        'Build with --dart-define=FIXNOW_ADMIN_API_URL=https://your-service. '
        'Development builds must configure their server explicitly.',
      );
    }
    final serviceUri = Uri.tryParse(_baseUrl);
    if (serviceUri == null ||
        !serviceUri.hasScheme ||
        !serviceUri.hasAuthority) {
      throw StateError('The FixNow administration service URL is invalid.');
    }
    if (const bool.fromEnvironment('dart.vm.product') &&
        serviceUri.scheme != 'https') {
      throw StateError(
        'The production administration service must use HTTPS.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Super Admin is not signed in.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain a Firebase access token.');
    }
    final request = http.Request(method, serviceUri.resolve(path))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw StateError(
            'FixNow administration service did not respond.',
          ),
        );
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw StateError(
        'Administration service returned an invalid response '
        '(HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['error'] as String? ?? 'Administration request failed.',
      );
    }
    return decoded;
  }

  bool _isMissingFirebaseAdminCredentials(StateError error) {
    return error.message.contains('missing Firebase Admin credentials');
  }

  Future<String> _createBranchAdminWithClientFallback({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String branchId,
  }) async {
    final actor = _auth.currentUser;
    if (actor == null) throw StateError('Super Admin is not signed in.');

    final branchRef = _firestore.collection('branches').doc(branchId);
    final branch = await branchRef.get();
    if (!branch.exists) throw StateError('Assigned branch was not found');
    final branchData = branch.data() ?? <String, dynamic>{};
    if (branchData['isActive'] == false) {
      throw StateError('Branch Admin cannot be assigned to an inactive branch');
    }

    final tempApp = await Firebase.initializeApp(
      name: 'branch-admin-creator-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
    UserCredential? createdCredential;
    try {
      createdCredential = await tempAuth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final createdUser = createdCredential.user;
      if (createdUser == null) {
        throw StateError('Unable to create Branch Admin account.');
      }
      await createdUser.updateDisplayName(name.trim());

      final uid = createdUser.uid;
      final userRef = _firestore.collection('users').doc(uid);
      final auditRef = _firestore.collection('audit_logs').doc();
      final branchName = branchData['name'] as String? ?? '';
      final profile = AppUser(
        uid: uid,
        name: name.trim(),
        email: email.trim().toLowerCase(),
        phone: phone.trim(),
        role: UserRole.branchAdmin,
        accountStatus: AccountStatus.approved,
        createdAt: DateTime.now(),
        isActive: true,
        branchId: branch.id,
        branchName: branchName,
      ).toJson()
        ..['createdAt'] = FieldValue.serverTimestamp()
        ..['createdBy'] = actor.uid;

      final batch = _firestore.batch();
      batch.set(userRef, profile);
      batch.update(branchRef, {
        'branchAdminIds': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, {
        'actorId': actor.uid,
        'actorRole': UserRole.superAdmin.name,
        'action': 'branchAdmin.created',
        'targetType': 'branchAdmin',
        'targetId': uid,
        'branchId': branch.id,
        'summary': 'Created Branch Admin ${email.trim().toLowerCase()}',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return uid;
    } catch (_) {
      await createdCredential?.user?.delete().catchError((_) {});
      rethrow;
    } finally {
      await tempAuth.signOut().catchError((_) {});
      await tempApp.delete().catchError((_) {});
    }
  }

  Future<void> _setBranchAdminActiveWithClientFallback({
    required String uid,
    required bool isActive,
  }) async {
    final actor = _auth.currentUser;
    if (actor == null) throw StateError('Super Admin is not signed in.');
    final userRef = _firestore.collection('users').doc(uid);
    final snapshot = await userRef.get();
    final data = snapshot.data();
    if (data == null || data['role'] != UserRole.branchAdmin.name) {
      throw StateError('Branch Admin account was not found.');
    }
    final auditRef = _firestore.collection('audit_logs').doc();
    final batch = _firestore.batch();
    batch.update(userRef, {
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(auditRef, {
      'actorId': actor.uid,
      'actorRole': UserRole.superAdmin.name,
      'action': isActive ? 'branchAdmin.activated' : 'branchAdmin.deactivated',
      'targetType': 'branchAdmin',
      'targetId': uid,
      if (data['branchId'] is String) 'branchId': data['branchId'],
      'summary': '${isActive ? 'Activated' : 'Deactivated'} Branch Admin '
          '${data['email'] ?? uid}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> _transferBranchAdminWithClientFallback({
    required String uid,
    required String branchId,
  }) async {
    final actor = _auth.currentUser;
    if (actor == null) throw StateError('Super Admin is not signed in.');
    final userRef = _firestore.collection('users').doc(uid);
    final destinationRef = _firestore.collection('branches').doc(branchId);
    final results = await Future.wait([userRef.get(), destinationRef.get()]);
    final userData = results[0].data();
    final branchData = results[1].data();
    if (userData == null || userData['role'] != UserRole.branchAdmin.name) {
      throw StateError('Branch Admin account was not found.');
    }
    if (branchData == null || branchData['isActive'] == false) {
      throw StateError('Destination branch is unavailable.');
    }
    final previousBranchId = userData['branchId'] as String?;
    final auditRef = _firestore.collection('audit_logs').doc();
    final batch = _firestore.batch();
    batch.update(userRef, {
      'branchId': branchId,
      'branchName': branchData['name'] as String? ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (previousBranchId != null && previousBranchId.isNotEmpty) {
      batch.update(_firestore.collection('branches').doc(previousBranchId), {
        'branchAdminIds': FieldValue.arrayRemove([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(destinationRef, {
      'branchAdminIds': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(auditRef, {
      'actorId': actor.uid,
      'actorRole': UserRole.superAdmin.name,
      'action': 'branchAdmin.transferred',
      'targetType': 'branchAdmin',
      'targetId': uid,
      'branchId': branchId,
      'summary': 'Transferred Branch Admin ${userData['email'] ?? uid} to '
          '${branchData['name'] ?? branchId}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> _transferTechnicianWithClientFallback({
    required String uid,
    required String branchId,
    required bool futureRevenueStaysWithPreviousBranch,
  }) async {
    final actor = _auth.currentUser;
    if (actor == null) throw StateError('Super Admin is not signed in.');
    final userRef = _firestore.collection('users').doc(uid);
    final destinationRef = _firestore.collection('branches').doc(branchId);
    final activeJobRef =
        _firestore.collection('technician_active_jobs').doc(uid);
    final results = await Future.wait([
      userRef.get(),
      destinationRef.get(),
      activeJobRef.get(),
    ]);
    final userData = results[0].data();
    final branchData = results[1].data();
    if (userData == null || userData['role'] != UserRole.technician.name) {
      throw StateError('Technician account was not found.');
    }
    if (branchData == null || branchData['isActive'] == false) {
      throw StateError('Destination branch is unavailable.');
    }
    if (results[2].exists) {
      throw StateError(
        'Complete the technician active job before changing branches.',
      );
    }
    final previousBranchId = userData['branchId'] as String?;
    final previousBranchName = userData['branchName'] as String?;
    final nativeBranchId =
        userData['nativeBranchId'] as String? ?? previousBranchId;
    final nativeBranchName =
        userData['nativeBranchName'] as String? ?? previousBranchName;
    if (nativeBranchId == null || nativeBranchId.isEmpty) {
      throw StateError('Technician native branch could not be determined.');
    }
    final auditRef = _firestore.collection('audit_logs').doc();
    // Lock legacy bills to the previous reporting branch before changing the
    // technician's future reporting branch. This never moves past revenue.
    final historicBills = await _firestore
        .collection('bills')
        .where('technicianId', isEqualTo: uid)
        .get();
    final futureRevenueBranchId =
        futureRevenueStaysWithPreviousBranch ? nativeBranchId : branchId;
    final futureRevenueBranchName = futureRevenueStaysWithPreviousBranch
        ? (nativeBranchName ?? nativeBranchId)
        : (branchData['name'] as String? ?? branchId);
    final legacyBills = historicBills.docs.where((bill) {
      return !((bill.data()['revenueBranchId'] as String?)?.trim().isNotEmpty ??
          false);
    }).toList();
    // Firestore batches permit at most 500 writes. Lock old bill ownership in
    // small batches before changing the future reporting branch.
    for (var start = 0; start < legacyBills.length; start += 450) {
      final ownershipBatch = _firestore.batch();
      for (final bill in legacyBills.skip(start).take(450)) {
        ownershipBatch.update(bill.reference, {
          'revenueBranchId': nativeBranchId,
          'revenueBranchLockedAt': FieldValue.serverTimestamp(),
        });
      }
      await ownershipBatch.commit();
    }
    final batch = _firestore.batch();
    batch.update(userRef, {
      'branchId': branchId,
      'branchName': branchData['name'] as String? ?? '',
      'nativeBranchId': futureRevenueBranchId,
      'nativeBranchName': futureRevenueBranchName,
      'transferredAt': FieldValue.serverTimestamp(),
      'transferredBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(auditRef, {
      'actorId': actor.uid,
      'actorRole': UserRole.superAdmin.name,
      'action': 'technician.transferred',
      'targetType': 'technician',
      'targetId': uid,
      'branchId': branchId,
      'previousRevenueBranchId': nativeBranchId,
      'futureRevenueBranchId': futureRevenueBranchId,
      'summary': 'Transferred technician ${userData['email'] ?? uid} to '
          '${branchData['name'] ?? branchId}; future revenue belongs to '
          '$futureRevenueBranchName. Existing bills remain with '
          '${nativeBranchName ?? nativeBranchId}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
