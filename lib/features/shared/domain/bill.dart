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
    this.branchId,
    this.paymentMode,
    this.paymentSubmittedAt,
    this.paymentConfirmedAt,
    this.paymentConfirmedBy,
    this.paymentApprovedAt,
    this.paymentApprovedBy,
    this.paidAt,
  });

  final String id;
  final String bookingId;
  final String customerId;
  final String technicianId;
  final double amount;
  final DateTime createdAt;
  final bool isPaid;
  final String? branchId;
  final String? paymentMode;
  final DateTime? paymentSubmittedAt;
  final DateTime? paymentConfirmedAt;
  final String? paymentConfirmedBy;
  final DateTime? paymentApprovedAt;
  final String? paymentApprovedBy;
  final DateTime? paidAt;

  DateTime get revenueDate =>
      paidAt ?? paymentApprovedAt ?? paymentConfirmedAt ?? createdAt;

  bool get hasPaymentForApproval =>
      !isPaid && (paymentMode ?? '').trim().isNotEmpty;

  String get paymentModeLabel {
    return switch ((paymentMode ?? '').trim()) {
      'cash' => 'Cash',
      'upi' => 'UPI',
      'card' => 'Card',
      'bankTransfer' => 'Bank transfer',
      'other' => 'Other',
      _ => 'Not recorded',
    };
  }

  String get paymentStatusLabel {
    if (isPaid) return 'Payment confirmed';
    if (hasPaymentForApproval) return 'Awaiting technician confirmation';
    return 'Payment due';
  }

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
      branchId: data['branchId'] as String?,
      paymentMode: data['paymentMode'] as String?,
      paymentSubmittedAt: (data['paymentSubmittedAt'] as Timestamp?)?.toDate(),
      paymentConfirmedAt: (data['paymentConfirmedAt'] as Timestamp?)?.toDate(),
      paymentConfirmedBy: data['paymentConfirmedBy'] as String?,
      paymentApprovedAt: (data['paymentApprovedAt'] as Timestamp?)?.toDate(),
      paymentApprovedBy: data['paymentApprovedBy'] as String?,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
    );
  }
}
