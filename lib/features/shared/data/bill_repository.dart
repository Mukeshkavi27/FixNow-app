import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/bill.dart';

final billRepositoryProvider = Provider<BillRepository>((ref) {
  return BillRepository(ref.watch(firebaseRefsProvider).firestore);
});

class BillRepository {
  BillRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<Bill?> watchForBooking(String bookingId) {
    return _firestore.collection('bills').doc(bookingId).snapshots().map(
          (doc) => doc.exists ? Bill.fromFirestore(doc) : null,
        );
  }

  Stream<List<Bill>> watchCustomerBills(String customerId) {
    return _firestore
        .collection('bills')
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snapshot) => _sortNewestFirst(
              snapshot.docs.map(Bill.fromFirestore).toList(),
            ));
  }

  Stream<List<Bill>> watchTechnicianBills(String technicianId) {
    return _firestore
        .collection('bills')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snapshot) => _sortNewestFirst(
              snapshot.docs.map(Bill.fromFirestore).toList(),
            ));
  }

  Stream<List<Bill>> watchAllBills({String? branchId}) {
    if (branchId == null || branchId.isEmpty) {
      return _firestore.collection('bills').snapshots().map(
            (snapshot) => _sortNewestFirst(
                snapshot.docs.map(Bill.fromFirestore).toList()),
          );
    }
    final revenueQuery = _firestore
        .collection('bills')
        .where('revenueBranchId', isEqualTo: branchId)
        .snapshots();
    final legacyQuery = _firestore
        .collection('bills')
        .where('branchId', isEqualTo: branchId)
        .snapshots();
    return _mergeBillQueries(revenueQuery, legacyQuery);
  }

  Stream<List<Bill>> _mergeBillQueries(
    Stream<QuerySnapshot<Map<String, dynamic>>> revenueQuery,
    Stream<QuerySnapshot<Map<String, dynamic>>> legacyQuery,
  ) {
    final controller = StreamController<List<Bill>>();
    List<Bill>? revenueBills;
    List<Bill>? legacyBills;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? revenueSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? legacySub;

    void emit() {
      if (revenueBills == null || legacyBills == null) return;
      final byId = <String, Bill>{
        for (final bill in legacyBills!) bill.id: bill,
        for (final bill in revenueBills!) bill.id: bill,
      };
      controller.add(_sortNewestFirst(byId.values.toList()));
    }

    controller.onListen = () {
      revenueSub = revenueQuery.listen(
        (snapshot) {
          revenueBills = snapshot.docs.map(Bill.fromFirestore).toList();
          emit();
        },
        onError: controller.addError,
      );
      legacySub = legacyQuery.listen(
        (snapshot) {
          legacyBills = snapshot.docs.map(Bill.fromFirestore).toList();
          emit();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await revenueSub?.cancel();
      await legacySub?.cancel();
    };
    return controller.stream;
  }

  List<Bill> _sortNewestFirst(List<Bill> bills) {
    bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return bills;
  }

  Future<void> generateBill({
    required String bookingId,
    required String customerId,
    required String technicianId,
    required double labourCharge,
    required double partsCharge,
    String? adjustmentReason,
  }) async {
    if (labourCharge < 0 || partsCharge < 0) {
      throw ArgumentError('Bill charges cannot be negative.');
    }
    final serviceAmount =
        double.parse((labourCharge + partsCharge).toStringAsFixed(2));
    if (serviceAmount <= 0) throw ArgumentError('Bill amount must be positive.');
    final cgstAmount = double.parse((serviceAmount * 0.09).toStringAsFixed(2));
    final sgstAmount = double.parse((serviceAmount * 0.09).toStringAsFixed(2));
    final payableAmount =
        double.parse((serviceAmount + cgstAmount + sgstAmount).toStringAsFixed(2));
    final billRef = _firestore.collection('bills').doc(bookingId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final technicianRef = _firestore.collection('users').doc(technicianId);
    await _firestore.runTransaction((transaction) async {
      final booking = await transaction.get(bookingRef);
      final technician = await transaction.get(technicianRef);
      final data = booking.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['status'] != BookingStatus.serviceCompleted.name ||
          data['customerId'] != customerId ||
          data['technicianId'] != technicianId) {
        throw StateError('Bill details do not match the completed booking.');
      }
      if (data['customerConfirmedWorkCompletedAt'] == null) {
        throw StateError(
          'Customer must confirm work completion before billing.',
        );
      }
      if (data['technicianCompletedWorkAt'] == null) {
        throw StateError(
          'Technician must request work completion before billing.',
        );
      }
      final technicianData = technician.data();
      if (technicianData == null || technicianData['role'] != 'technician') {
        throw StateError('Technician account not found.');
      }
      final revenueBranchId = technicianData['nativeBranchId'] as String? ??
          technicianData['branchId'] as String? ??
          data['branchId'] as String?;
      transaction.set(billRef, {
        'bookingId': bookingId,
        'customerId': customerId,
        'technicianId': technicianId,
        'branchId': data['branchId'],
        'revenueBranchId': revenueBranchId,
        // `amount` is always the final amount payable and is what payment and
        // collection reports use. Tax values are retained for the invoice.
        'amount': payableAmount,
        'serviceAmount': serviceAmount,
        'labourCharge': double.parse(labourCharge.toStringAsFixed(2)),
        'partsCharge': double.parse(partsCharge.toStringAsFixed(2)),
        'adjustmentReason': adjustmentReason?.trim().isEmpty ?? true
            ? null
            : adjustmentReason!.trim(),
        'cgstAmount': cgstAmount,
        'sgstAmount': sgstAmount,
        'cgstRate': 9,
        'sgstRate': 9,
        'applianceType': data['applianceType'],
        'customerName': data['customerName'],
        'technicianName': data['technicianName'],
        'serviceAddress': data['address'],
        'preferredTime': data['preferredTime'],
        'technicianCompletedWorkAt': data['technicianCompletedWorkAt'],
        'customerConfirmedWorkCompletedAt':
            data['customerConfirmedWorkCompletedAt'],
        'createdAt': FieldValue.serverTimestamp(),
        'isPaid': false,
        'paymentMode': null,
        'amountReceived': null,
        'paymentProofUrl': null,
        'paymentSubmittedAt': null,
        'paymentConfirmedAt': null,
        'paymentConfirmedBy': null,
        'paymentApprovedAt': null,
        'paymentApprovedBy': null,
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.billGenerated.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_firestore.collection('notifications').doc(), {
        'userId': customerId,
        'bookingId': bookingId,
        'type': 'billGenerated',
        'title': 'Final bill generated',
        'body': 'Your final service bill is ready.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> confirmCollectedPayment({
    required String bookingId,
    required String technicianId,
    required String paymentMode,
    required double amountReceived,
    String? paymentProofUrl,
  }) async {
    final normalizedMode = paymentMode.trim();
    if (normalizedMode.isEmpty) {
      throw ArgumentError('Select the payment mode.');
    }
    if (amountReceived <= 0) {
      throw ArgumentError('Enter the amount received.');
    }
    if (normalizedMode != 'cash' &&
        (paymentProofUrl == null || paymentProofUrl.trim().isEmpty)) {
      throw ArgumentError('Upload payment proof for online payment.');
    }
    final billRef = _firestore.collection('bills').doc(bookingId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final bill = await transaction.get(billRef);
      final booking = await transaction.get(bookingRef);
      if (!bill.exists || !booking.exists) {
        throw StateError('Bill or booking not found.');
      }
      final billData = bill.data();
      if (billData == null) throw StateError('Bill not found.');
      if (billData['technicianId'] != technicianId) {
        throw StateError('This bill is assigned to another technician.');
      }
      if (billData['isPaid'] == true) {
        throw StateError('This payment is already approved.');
      }
      final bookingData = booking.data();
      if (bookingData?['status'] != BookingStatus.billGenerated.name) {
        throw StateError('Payment can only be confirmed after final bill.');
      }
      if ((billData['amount'] as num).toDouble() != amountReceived) {
        throw StateError('Received amount must match the final bill amount.');
      }
      transaction.update(billRef, {
        // Technician confirmation records what was received. The customer
        // must still verify it before the bill is paid and the booking closes.
        'isPaid': false,
        'paymentMode': normalizedMode,
        'amountReceived': amountReceived,
        'paymentProofUrl': paymentProofUrl,
        'paymentSubmittedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedBy': technicianId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_firestore.collection('notifications').doc(), {
        'userId': billData['customerId'],
        'bookingId': bookingId,
        'type': 'paymentSubmitted',
        'title': 'Confirm payment received',
        'body':
            'Your technician recorded the payment. Please verify the amount and confirm to complete the service.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> submitCollectedPayment({
    required String bookingId,
    required String technicianId,
    required String paymentMode,
    required double amountReceived,
    String? paymentProofUrl,
  }) {
    return confirmCollectedPayment(
      bookingId: bookingId,
      technicianId: technicianId,
      paymentMode: paymentMode,
      amountReceived: amountReceived,
      paymentProofUrl: paymentProofUrl,
    );
  }

  Future<void> approvePayment({
    required String bookingId,
    required String customerId,
  }) async {
    final billRef = _firestore.collection('bills').doc(bookingId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final bill = await transaction.get(billRef);
      final booking = await transaction.get(bookingRef);
      if (!bill.exists || !booking.exists) {
        throw StateError('Bill or booking not found.');
      }
      final billData = bill.data();
      if (billData == null) throw StateError('Bill not found.');
      if (billData['isPaid'] == true) {
        throw StateError('This payment is already approved.');
      }
      if (billData['customerId'] != customerId) {
        throw StateError('You can only confirm your own payment.');
      }
      final paymentMode = billData['paymentMode'] as String?;
      if (paymentMode == null || paymentMode.trim().isEmpty) {
        throw StateError('Technician has not submitted payment mode yet.');
      }
      if ((billData['amountReceived'] as num?)?.toDouble() !=
          (billData['amount'] as num?)?.toDouble()) {
        throw StateError('The recorded payment amount does not match the bill.');
      }
      transaction.update(billRef, {
        'isPaid': true,
        'paidAt': FieldValue.serverTimestamp(),
        'paymentApprovedAt': FieldValue.serverTimestamp(),
        'paymentApprovedBy': customerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.closed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
