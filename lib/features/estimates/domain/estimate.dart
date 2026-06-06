import 'package:cloud_firestore/cloud_firestore.dart';

class Estimate {
  const Estimate({
    required this.id,
    required this.bookingId,
    required this.technicianId,
    required this.labourCharge,
    required this.partsCharge,
    required this.notes,
    required this.isApproved,
    required this.createdAt,
  });

  final String id;
  final String bookingId;
  final String technicianId;
  final double labourCharge;
  final double partsCharge;
  final String notes;
  final bool isApproved;
  final DateTime createdAt;

  double get total => labourCharge + partsCharge;

  factory Estimate.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Estimate(
      id: doc.id,
      bookingId: data['bookingId'] as String? ?? '',
      technicianId: data['technicianId'] as String? ?? '',
      labourCharge: (data['labourCharge'] as num?)?.toDouble() ?? 0,
      partsCharge: (data['partsCharge'] as num?)?.toDouble() ?? 0,
      notes: data['notes'] as String? ?? '',
      isApproved: data['isApproved'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'technicianId': technicianId,
        'labourCharge': labourCharge,
        'partsCharge': partsCharge,
        'notes': notes,
        'isApproved': isApproved,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
