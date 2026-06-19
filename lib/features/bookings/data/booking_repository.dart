import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/booking.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(firebaseRefsProvider).firestore);
});

class BookingRepository {
  BookingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<Booking>> watchCustomerBookings(String customerId) {
    return _firestore
        .collection('bookings')
        .where('customerId', isEqualTo: customerId)
        .snapshots()
        .map((snapshot) => _sortNewestFirst(
            snapshot.docs.map(Booking.fromFirestore).toList()));
  }

  Stream<List<Booking>> watchTechnicianBookings(String technicianId) {
    return _firestore
        .collection('bookings')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snapshot) => _sortNewestFirst(
            snapshot.docs.map(Booking.fromFirestore).toList()));
  }

  Stream<List<Booking>> watchAllBookings() {
    return _firestore
        .collection('bookings')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Booking.fromFirestore).toList());
  }

  List<Booking> _sortNewestFirst(List<Booking> bookings) {
    bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return bookings;
  }

  Stream<Booking?> watchBooking(String id) {
    return _firestore.collection('bookings').doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Booking.fromFirestore(doc);
    });
  }

  Future<String> createBooking(Booking booking) async {
    final doc = _firestore.collection('bookings').doc();
    await doc.set({
      ...booking.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> rescheduleUnassignedBooking({
    required String bookingId,
    required String customerId,
    required DateTime preferredDate,
    required String preferredTime,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId ||
          data['status'] != BookingStatus.booked.name ||
          data['technicianId'] != null) {
        throw StateError(
          'This booking can no longer be rescheduled.',
        );
      }
      transaction.update(bookingRef, {
        'preferredDate': Timestamp.fromDate(preferredDate),
        'preferredTime': preferredTime,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelUnassignedBooking({
    required String bookingId,
    required String customerId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId ||
          data['status'] != BookingStatus.booked.name ||
          data['technicianId'] != null) {
        throw StateError('This booking can no longer be cancelled.');
      }
      transaction.delete(bookingRef);
    });
  }

  Future<void> transitionStatus({
    required String bookingId,
    required String technicianId,
    required BookingStatus expected,
    required BookingStatus next,
  }) {
    if (!expected.canTransitionTo(next)) {
      throw StateError('Invalid booking transition: $expected -> $next');
    }
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['technicianId'] != technicianId) {
        throw StateError('This booking is not assigned to this technician.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current != expected) {
        throw StateError('Booking is already ${current.label}.');
      }
      transaction.update(bookingRef, {
        'status': next.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> addServicePhoto({
    required String bookingId,
    required String stage,
    required String url,
  }) {
    return _firestore.collection('bookings').doc(bookingId).update({
      'servicePhotos': FieldValue.arrayUnion([
        {
          'stage': stage,
          'url': url,
          'uploadedAt': Timestamp.now(),
        }
      ]),
    });
  }

  Future<void> assignTechnician({
    required String bookingId,
    required String technicianId,
    required String technicianName,
  }) async {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['status'] != BookingStatus.booked.name) {
        throw StateError('Only unassigned bookings can be assigned.');
      }
      transaction.update(bookingRef, {
        'technicianId': technicianId,
        'technicianName': technicianName,
        'status': BookingStatus.technicianAssigned.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectAssignment({
    required String bookingId,
    required String technicianId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['technicianId'] != technicianId ||
          data['status'] != BookingStatus.technicianAssigned.name) {
        throw StateError('This assignment can no longer be rejected.');
      }
      transaction.update(bookingRef, {
        'technicianId': FieldValue.delete(),
        'technicianName': FieldValue.delete(),
        'status': BookingStatus.booked.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
