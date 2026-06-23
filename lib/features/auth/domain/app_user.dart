import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';

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
    this.requestLatitude,
    this.requestLongitude,
    this.profilePhoto,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final AccountStatus accountStatus;
  final String? profilePhoto;
  final DateTime createdAt;
  final bool isActive;
  final String? branchId;
  final String? branchName;
  final double? requestLatitude;
  final double? requestLongitude;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      uid: data['uid'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      role: UserRole.fromString(data['role'] as String? ?? 'customer'),
      accountStatus:
          AccountStatus.fromString(data['accountStatus'] as String?),
      profilePhoto: data['profilePhoto'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] as bool? ?? true,
      branchId: data['branchId'] as String?,
      branchName: data['branchName'] as String?,
      requestLatitude: (data['requestLatitude'] as num?)?.toDouble(),
      requestLongitude: (data['requestLongitude'] as num?)?.toDouble(),
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
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'branchId': branchId,
      'branchName': branchName,
      'requestLatitude': requestLatitude,
      'requestLongitude': requestLongitude,
    };
  }
}
