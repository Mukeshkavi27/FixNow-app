import 'package:cloud_firestore/cloud_firestore.dart';

class TechnicianIncentive {
  const TechnicianIncentive({
    required this.id,
    required this.technicianId,
    required this.branchId,
    this.revenueBranchId,
    required this.amount,
    required this.description,
    required this.awardedAt,
    required this.awardedBy,
  });

  final String id;
  final String technicianId;
  final String branchId;
  final String? revenueBranchId;
  final double amount;
  final String description;
  final DateTime awardedAt;
  final String awardedBy;

  factory TechnicianIncentive.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TechnicianIncentive(
      id: doc.id,
      technicianId: data['technicianId'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      revenueBranchId: data['revenueBranchId'] as String?,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String? ?? '',
      awardedAt: (data['awardedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      awardedBy: data['awardedBy'] as String? ?? '',
    );
  }
}
