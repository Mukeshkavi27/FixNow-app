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

  Stream<List<Bill>> watchAllBills() {
    return _firestore.collection('bills').snapshots().map(
          (snapshot) =>
              _sortNewestFirst(snapshot.docs.map(Bill.fromFirestore).toList()),
        );
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
    await _firestore.runTransaction((transaction) async {
      final booking = await transaction.get(bookingRef);
      final data = booking.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['status'] != BookingStatus.serviceCompleted.name ||
          data['customerId'] != customerId ||
          data['technicianId'] != technicianId) {
        throw StateError('Bill details do not match the completed booking.');
      }
      transaction.set(billRef, {
        'bookingId': bookingId,
        'customerId': customerId,
        'technicianId': technicianId,
        'amount': amount,
        'createdAt': FieldValue.serverTimestamp(),
        'isPaid': false,
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.billGenerated.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markPaid(String bookingId) async {
    final billRef = _firestore.collection('bills').doc(bookingId);
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final bill = await transaction.get(billRef);
      final booking = await transaction.get(bookingRef);
      if (!bill.exists || !booking.exists) {
        throw StateError('Bill or booking not found.');
      }
      transaction.update(billRef, {
        'isPaid': true,
        'paidAt': FieldValue.serverTimestamp(),
      });
      transaction.update(bookingRef, {
        'status': BookingStatus.closed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
