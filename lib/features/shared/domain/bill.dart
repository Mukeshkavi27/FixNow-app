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
    this.serviceAmount,
    this.labourCharge,
    this.partsCharge,
    this.adjustmentReason,
    this.cgstAmount,
    this.sgstAmount,
    this.branchId,
    this.revenueBranchId,
    this.applianceType,
    this.customerName,
    this.technicianName,
    this.serviceAddress,
    this.preferredTime,
    this.technicianCompletedWorkAt,
    this.customerConfirmedWorkCompletedAt,
    this.paymentMode,
    this.amountReceived,
    this.paymentProofUrl,
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
  /// Pre-tax service charge. Legacy bills use [amount] as their total.
  final double? serviceAmount;
  /// Actual on-site charges entered by the technician for the final invoice.
  final double? labourCharge;
  final double? partsCharge;
  final String? adjustmentReason;
  final double? cgstAmount;
  final double? sgstAmount;
  final String? branchId;
  final String? revenueBranchId;
  final String? applianceType;
  final String? customerName;
  final String? technicianName;
  final String? serviceAddress;
  final String? preferredTime;
  final DateTime? technicianCompletedWorkAt;
  final DateTime? customerConfirmedWorkCompletedAt;
  final String? paymentMode;
  final double? amountReceived;
  final String? paymentProofUrl;
  final DateTime? paymentSubmittedAt;
  final DateTime? paymentConfirmedAt;
  final String? paymentConfirmedBy;
  final DateTime? paymentApprovedAt;
  final String? paymentApprovedBy;
  final DateTime? paidAt;

  DateTime get revenueDate =>
      paidAt ?? paymentApprovedAt ?? paymentConfirmedAt ?? createdAt;

  double get taxableAmount => serviceAmount ?? amount;
  double get cgst => cgstAmount ?? 0;
  double get sgst => sgstAmount ?? 0;
  double get totalTax => cgst + sgst;

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
    if (hasPaymentForApproval) return 'Awaiting customer confirmation';
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
      serviceAmount: (data['serviceAmount'] as num?)?.toDouble(),
      labourCharge: (data['labourCharge'] as num?)?.toDouble(),
      partsCharge: (data['partsCharge'] as num?)?.toDouble(),
      adjustmentReason: data['adjustmentReason'] as String?,
      cgstAmount: (data['cgstAmount'] as num?)?.toDouble(),
      sgstAmount: (data['sgstAmount'] as num?)?.toDouble(),
      branchId: data['branchId'] as String?,
      revenueBranchId: data['revenueBranchId'] as String?,
      applianceType: data['applianceType'] as String?,
      customerName: data['customerName'] as String?,
      technicianName: data['technicianName'] as String?,
      serviceAddress: data['serviceAddress'] as String?,
      preferredTime: data['preferredTime'] as String?,
      technicianCompletedWorkAt:
          (data['technicianCompletedWorkAt'] as Timestamp?)?.toDate(),
      customerConfirmedWorkCompletedAt:
          (data['customerConfirmedWorkCompletedAt'] as Timestamp?)?.toDate(),
      paymentMode: data['paymentMode'] as String?,
      amountReceived: (data['amountReceived'] as num?)?.toDouble(),
      paymentProofUrl: data['paymentProofUrl'] as String?,
      paymentSubmittedAt: (data['paymentSubmittedAt'] as Timestamp?)?.toDate(),
      paymentConfirmedAt: (data['paymentConfirmedAt'] as Timestamp?)?.toDate(),
      paymentConfirmedBy: data['paymentConfirmedBy'] as String?,
      paymentApprovedAt: (data['paymentApprovedAt'] as Timestamp?)?.toDate(),
      paymentApprovedBy: data['paymentApprovedBy'] as String?,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
    );
  }
}
