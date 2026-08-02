import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/enums/technician_category.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.createdAt,
    required this.isActive,
    this.accountStatus = AccountStatus.approved,
    this.branchId,
    this.branchName,
    this.nativeBranchId,
    this.nativeBranchName,
    this.requestLatitude,
    this.requestLongitude,
    this.profilePhoto,
    this.faceReferencePhoto,
    this.faceReferenceSignature,
    this.faceReferenceUpdatedAt,
    this.lastServiceAddress,
    this.lastServiceLatitude,
    this.lastServiceLongitude,
    this.approvedAt,
    this.approvedBy,
    this.rejectionReason,
    this.rejectedAt,
    this.rejectedBy,
    this.inactivatedAt,
    this.inactivatedBy,
    this.inactivationReason,
    this.reactivatedAt,
    this.reactivatedBy,
    this.transferredAt,
    this.transferredBy,
    this.technicianCategory = TechnicianCategory.junior,
    this.monthlySalary = 0,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final AccountStatus accountStatus;
  final String? profilePhoto;
  final String? faceReferencePhoto;
  final String? faceReferenceSignature;
  final DateTime? faceReferenceUpdatedAt;
  final DateTime createdAt;
  final bool isActive;
  final String? branchId;
  final String? branchName;
  final String? nativeBranchId;
  final String? nativeBranchName;
  final double? requestLatitude;
  final double? requestLongitude;
  final String? lastServiceAddress;
  final double? lastServiceLatitude;
  final double? lastServiceLongitude;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final DateTime? inactivatedAt;
  final String? inactivatedBy;
  final String? inactivationReason;
  final DateTime? reactivatedAt;
  final String? reactivatedBy;
  final DateTime? transferredAt;
  final String? transferredBy;
  final TechnicianCategory technicianCategory;
  final double monthlySalary;

  bool get hasValidBranchAssignment =>
      role != UserRole.branchAdmin || (branchId?.trim().isNotEmpty ?? false);

  String? get accessDenialReason {
    if (accountStatus == AccountStatus.pendingApproval) {
      return 'Your account is waiting for approval.';
    }
    if (accountStatus == AccountStatus.rejected) {
      final reason = rejectionReason?.trim();
      return reason == null || reason.isEmpty
          ? 'Your account request was rejected. Contact your branch administrator.'
          : 'Your account request was rejected: $reason';
    }
    if (!isActive) {
      return 'Your account is inactive. Contact your FixNow administrator.';
    }
    if (!hasValidBranchAssignment) {
      return 'This Branch Admin account is not assigned to a branch.';
    }
    return null;
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      uid: data['uid'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      role: UserRole.fromString(data['role'] as String? ?? 'customer'),
      accountStatus: AccountStatus.fromString(data['accountStatus'] as String?),
      profilePhoto: data['profilePhoto'] as String?,
      faceReferencePhoto: data['faceReferencePhoto'] as String?,
      faceReferenceSignature: data['faceReferenceSignature'] as String?,
      faceReferenceUpdatedAt:
          (data['faceReferenceUpdatedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] as bool? ?? true,
      branchId: data['branchId'] as String?,
      branchName: data['branchName'] as String?,
      nativeBranchId: data['nativeBranchId'] as String? ??
          (data['role'] == UserRole.technician.name
              ? data['branchId'] as String?
              : null),
      nativeBranchName: data['nativeBranchName'] as String? ??
          (data['role'] == UserRole.technician.name
              ? data['branchName'] as String?
              : null),
      requestLatitude: (data['requestLatitude'] as num?)?.toDouble(),
      requestLongitude: (data['requestLongitude'] as num?)?.toDouble(),
      lastServiceAddress: data['lastServiceAddress'] as String?,
      lastServiceLatitude: (data['lastServiceLatitude'] as num?)?.toDouble(),
      lastServiceLongitude: (data['lastServiceLongitude'] as num?)?.toDouble(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      approvedBy: data['approvedBy'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      rejectedAt: (data['rejectedAt'] as Timestamp?)?.toDate(),
      rejectedBy: data['rejectedBy'] as String?,
      inactivatedAt: (data['inactivatedAt'] as Timestamp?)?.toDate(),
      inactivatedBy: data['inactivatedBy'] as String?,
      inactivationReason: data['inactivationReason'] as String?,
      reactivatedAt: (data['reactivatedAt'] as Timestamp?)?.toDate(),
      reactivatedBy: data['reactivatedBy'] as String?,
      transferredAt: (data['transferredAt'] as Timestamp?)?.toDate(),
      transferredBy: data['transferredBy'] as String?,
      technicianCategory: TechnicianCategory.fromString(
        data['technicianCategory'] as String?,
      ),
      monthlySalary: (data['monthlySalary'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.name,
      'accountStatus': accountStatus.name,
      'profilePhoto': profilePhoto,
      'faceReferencePhoto': faceReferencePhoto,
      'faceReferenceSignature': faceReferenceSignature,
      'faceReferenceUpdatedAt': faceReferenceUpdatedAt == null
          ? null
          : Timestamp.fromDate(faceReferenceUpdatedAt!),
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'branchId': branchId,
      'branchName': branchName,
      if (role == UserRole.technician)
        'nativeBranchId': nativeBranchId ?? branchId,
      if (role == UserRole.technician)
        'nativeBranchName': nativeBranchName ?? branchName,
      'requestLatitude': requestLatitude,
      'requestLongitude': requestLongitude,
      'lastServiceAddress': lastServiceAddress,
      'lastServiceLatitude': lastServiceLatitude,
      'lastServiceLongitude': lastServiceLongitude,
      'approvedAt': approvedAt == null ? null : Timestamp.fromDate(approvedAt!),
      'approvedBy': approvedBy,
      'rejectionReason': rejectionReason,
      'rejectedAt': rejectedAt == null ? null : Timestamp.fromDate(rejectedAt!),
      'rejectedBy': rejectedBy,
      'inactivatedAt':
          inactivatedAt == null ? null : Timestamp.fromDate(inactivatedAt!),
      'inactivatedBy': inactivatedBy,
      'inactivationReason': inactivationReason,
      'reactivatedAt':
          reactivatedAt == null ? null : Timestamp.fromDate(reactivatedAt!),
      'reactivatedBy': reactivatedBy,
      'transferredAt':
          transferredAt == null ? null : Timestamp.fromDate(transferredAt!),
      'transferredBy': transferredBy,
      if (role == UserRole.technician)
        'technicianCategory': technicianCategory.name,
      if (role == UserRole.technician) 'monthlySalary': monthlySalary,
    };
  }
}
