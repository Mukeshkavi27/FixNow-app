import 'package:cloud_firestore/cloud_firestore.dart';

class Bill {
  const Bill({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.technicianId,
    required this.amount,
    required this.createdAt,
    required this.isPaid,
  });

  final String id;
  final String bookingId;
  final String customerId;
  final String technicianId;
  final double amount;
  final DateTime createdAt;
  final bool isPaid;

  factory Bill.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Bill(
      id: doc.id,
      bookingId: data['bookingId'] as String? ?? '',
      customerId: data['customerId'] as String? ?? '',
      technicianId: data['technicianId'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPaid: data['isPaid'] as bool? ?? false,
    );
  }
}
