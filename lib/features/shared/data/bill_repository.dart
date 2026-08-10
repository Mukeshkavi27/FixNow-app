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
    required double amount,
  }) async {
    if (amount <= 0) throw ArgumentError('Bill amount must be positive.');
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
        'amount': amount,
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
  }) async {
    final normalizedMode = paymentMode.trim();
    if (normalizedMode.isEmpty) {
      throw ArgumentError('Select the payment mode.');
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
      transaction.update(billRef, {
        'isPaid': true,
        'paymentMode': normalizedMode,
        'paymentSubmittedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedBy': technicianId,
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.closed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_firestore.collection('notifications').doc(), {
        'userId': billData['customerId'],
        'bookingId': bookingId,
        'type': 'paymentConfirmed',
        'title': 'Payment confirmed',
        'body': 'Your technician confirmed the payment. The job is now closed.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> submitCollectedPayment({
    required String bookingId,
    required String technicianId,
    required String paymentMode,
  }) {
    return confirmCollectedPayment(
      bookingId: bookingId,
      technicianId: technicianId,
      paymentMode: paymentMode,
    );
  }

  Future<void> approvePayment({
    required String bookingId,
    String? approvedBy,
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
      final paymentMode = billData['paymentMode'] as String?;
      if (paymentMode == null || paymentMode.trim().isEmpty) {
        throw StateError('Technician has not submitted payment mode yet.');
      }
      transaction.update(billRef, {
        'isPaid': true,
        'paidAt': FieldValue.serverTimestamp(),
        'paymentApprovedAt': FieldValue.serverTimestamp(),
        'paymentApprovedBy': approvedBy,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.closed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markPaid(String bookingId) {
    return approvePayment(bookingId: bookingId);
  }
}
