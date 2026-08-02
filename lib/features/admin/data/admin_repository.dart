import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/enums/technician_category.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(firebaseRefsProvider).firestore);
});

String normalizeTechnicianRejectionReason(String value) {
  final reason = value.trim();
  if (reason.length < 5) {
    throw ArgumentError('Enter a clear rejection reason.');
  }
  return reason;
}

String normalizeTechnicianInactivationReason(String value) {
  final reason = value.trim();
  if (reason.length < 5) {
    throw ArgumentError('Enter a clear inactivation reason.');
  }
  return reason;
}

bool isTechnicianAssignable(AppUser technician) =>
    technician.role == UserRole.technician &&
    technician.isActive &&
    technician.accountStatus == AccountStatus.approved;

class AdminRepository {
  AdminRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> updateTechnicianCategory({
    required String uid,
    required TechnicianCategory category,
    required String actorId,
    required String branchId,
  }) {
    return _updateBranchTechnician(
      uid: uid,
      actorId: actorId,
      branchId: branchId,
      action: 'technician.categoryUpdated',
      summary: 'Technician category changed to ${category.label}',
      updates: {
        'technicianCategory': category.name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> updateTechnicianSalary({
    required String uid,
    required double monthlySalary,
    required String actorId,
    required String branchId,
  }) {
    if (!monthlySalary.isFinite || monthlySalary < 0) {
      throw ArgumentError('Enter a valid monthly salary.');
    }
    return _updateBranchTechnician(
      uid: uid,
      actorId: actorId,
      branchId: branchId,
      action: 'technician.salaryUpdated',
      summary: 'Technician monthly salary changed to Rs. '
          '${monthlySalary.toStringAsFixed(0)}',
      updates: {
        'monthlySalary': monthlySalary,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Stream<List<AppUser>> watchTechnicians({String? branchId}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(AppUser.fromFirestore).toList(),
        );
  }

  Stream<List<AppUser>> watchTechniciansVisibleToBranch(String branchId) {
    final currentQuery = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name)
        .where('branchId', isEqualTo: branchId)
        .snapshots();
    final nativeQuery = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name)
        .where('nativeBranchId', isEqualTo: branchId)
        .snapshots();
    final controller = StreamController<List<AppUser>>();
    List<AppUser>? currentUsers;
    List<AppUser>? nativeUsers;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? currentSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? nativeSub;

    void emit() {
      if (currentUsers == null || nativeUsers == null) return;
      final byId = <String, AppUser>{
        for (final user in currentUsers!) user.uid: user,
        for (final user in nativeUsers!) user.uid: user,
      };
      controller.add(byId.values.toList());
    }

    controller.onListen = () {
      currentSub = currentQuery.listen((snapshot) {
        currentUsers = snapshot.docs.map(AppUser.fromFirestore).toList();
        emit();
      }, onError: controller.addError);
      nativeSub = nativeQuery.listen((snapshot) {
        nativeUsers = snapshot.docs.map(AppUser.fromFirestore).toList();
        emit();
      }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await currentSub?.cancel();
      await nativeSub?.cancel();
    };
    return controller.stream;
  }

  Stream<List<AppUser>> watchCustomers({String? branchId}) {
    var query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.customer.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Stream<List<AppUser>> watchPendingTechnicianRequests({String? branchId}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.technician.name)
        .where('accountStatus', isEqualTo: AccountStatus.pendingApproval.name);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(AppUser.fromFirestore).toList(),
        );
  }

  Future<void> setTechnicianActive({
    required String uid,
    required bool isActive,
    required String actorId,
    required String branchId,
    String? reason,
  }) {
    final inactivationReason =
        isActive ? null : normalizeTechnicianInactivationReason(reason ?? '');
    return _updateBranchTechnician(
      uid: uid,
      actorId: actorId,
      branchId: branchId,
      action: isActive ? 'technician.reactivated' : 'technician.inactivated',
      summary: isActive
          ? 'Technician account reactivated by Branch Admin'
          : 'Technician account inactivated: $inactivationReason',
      updates: isActive
          ? {
              'isActive': true,
              'reactivatedAt': FieldValue.serverTimestamp(),
              'reactivatedBy': actorId,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          : {
              'isActive': false,
              'inactivatedAt': FieldValue.serverTimestamp(),
              'inactivatedBy': actorId,
              'inactivationReason': inactivationReason,
              'updatedAt': FieldValue.serverTimestamp(),
            },
      requireApproved: isActive,
    );
  }

  Future<void> approveTechnicianRequest({
    required String uid,
    required String branchId,
    required String branchName,
    required String actorId,
  }) {
    return _updateBranchTechnician(
      uid: uid,
      actorId: actorId,
      branchId: branchId,
      action: 'technician.approved',
      summary: 'Technician registration approved by Branch Admin',
      updates: {
        'isActive': true,
        'accountStatus': AccountStatus.approved.name,
        'branchName': branchName,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': actorId,
        'rejectionReason': FieldValue.delete(),
        'rejectedAt': FieldValue.delete(),
        'rejectedBy': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      requirePending: true,
      decisionType: 'technicianApproved',
      decisionBody: 'Your technician account for $branchName was approved.',
    );
  }

  Future<void> rejectTechnicianRequest({
    required String uid,
    required String actorId,
    required String branchId,
    required String reason,
  }) {
    final rejectionReason = normalizeTechnicianRejectionReason(reason);
    return _updateBranchTechnician(
      uid: uid,
      actorId: actorId,
      branchId: branchId,
      action: 'technician.rejected',
      summary: 'Technician registration rejected: $rejectionReason',
      updates: {
        'isActive': false,
        'accountStatus': AccountStatus.rejected.name,
        'approvedAt': FieldValue.delete(),
        'approvedBy': FieldValue.delete(),
        'rejectionReason': rejectionReason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': actorId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      requirePending: true,
      decisionType: 'technicianRejected',
      decisionBody: 'Your technician request was rejected: $rejectionReason',
    );
  }

  Future<void> _updateBranchTechnician({
    required String uid,
    required String actorId,
    required String branchId,
    required String action,
    required String summary,
    required Map<String, Object?> updates,
    bool requireApproved = false,
    bool requirePending = false,
    String? decisionType,
    String? decisionBody,
  }) {
    final technicianRef = _firestore.collection('users').doc(uid);
    final auditRef = _firestore.collection('audit_logs').doc();
    final registrationNotificationRef = _firestore
        .collection('notifications')
        .doc('technician_registration_$uid');
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(technicianRef);
      final registrationNotification = requirePending
          ? await transaction.get(registrationNotificationRef)
          : null;
      final data = snapshot.data();
      if (data == null) throw StateError('Technician account not found.');
      if (data['role'] != UserRole.technician.name) {
        throw StateError('Only technician accounts can be managed here.');
      }
      if (data['branchId'] != branchId) {
        throw StateError('This technician belongs to another branch.');
      }
      if (requireApproved &&
          data['accountStatus'] != AccountStatus.approved.name) {
        throw StateError('Only approved technicians can be reactivated.');
      }
      if (requirePending &&
          data['accountStatus'] != AccountStatus.pendingApproval.name) {
        throw StateError('This technician request was already reviewed.');
      }
      transaction.update(technicianRef, updates);
      if (registrationNotification?.exists == true) {
        transaction.update(registrationNotificationRef, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(auditRef, {
        'actorId': actorId,
        'actorRole': UserRole.branchAdmin.name,
        'branchId': branchId,
        'action': action,
        'targetType': 'technician',
        'targetId': uid,
        'summary': summary,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (decisionType != null && decisionBody != null) {
        transaction.set(_firestore.collection('notifications').doc(), {
          'userId': uid,
          'recipientRole': UserRole.technician.name,
          'technicianId': uid,
          'branchId': branchId,
          'type': decisionType,
          'title': decisionType == 'technicianApproved'
              ? 'Technician account approved'
              : 'Technician request rejected',
          'body': decisionBody,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
