import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

const _configuredAdminApiUrl = String.fromEnvironment(
  'FIXNOW_ADMIN_API_URL',
  defaultValue: '',
);
const _localAdminApiUrl = 'http://127.0.0.1:8088';
const _adminApiUrl =
    _configuredAdminApiUrl == '' && !bool.fromEnvironment('dart.vm.product')
        ? _localAdminApiUrl
        : _configuredAdminApiUrl;

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
    String baseUrl = _adminApiUrl,
  })  : _auth = auth,
        _firestore = firestore,
        _client = client,
        _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final http.Client _client;
  final String _baseUrl;

  Future<String> createBranchAdmin({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String branchId,
  }) async {
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
    return _send(
      'PATCH',
      '/api/admin/branch-admins/$uid/branch',
      body: {'branchId': branchId},
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
        'Local debug builds default to $_localAdminApiUrl.',
      );
    }
    final serviceUri = Uri.tryParse(_baseUrl);
    if (serviceUri == null ||
        !serviceUri.hasScheme ||
        !serviceUri.hasAuthority) {
      throw StateError('The FixNow administration service URL is invalid.');
    }
    final isLocalService =
        (serviceUri.host == 'localhost' || serviceUri.host == '127.0.0.1') &&
            serviceUri.scheme == 'http';
    if (const bool.fromEnvironment('dart.vm.product') &&
        serviceUri.scheme != 'https' &&
        !isLocalService) {
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
}
