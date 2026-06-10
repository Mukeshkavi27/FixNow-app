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
    final doc = await _firestore.collection('bookings').add(booking.toJson());
    await _firestore.collection('notifications').add({
      'role': 'admin',
      'title': 'New Booking',
      'body':
          '${booking.applianceType} service requested by ${booking.customerName}',
      'bookingId': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
    return doc.id;
  }

  Future<void> updateStatus(String bookingId, BookingStatus status) {
    return _firestore
        .collection('bookings')
        .doc(bookingId)
        .update({'status': status.name});
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
          'uploadedAt': Timestamp.fromDate(DateTime.now()),
        }
      ]),
    });
  }

  Future<void> assignTechnician({
    required String bookingId,
    required String technicianId,
    required String technicianName,
  }) async {
    await _firestore.collection('bookings').doc(bookingId).update({
      'technicianId': technicianId,
      'technicianName': technicianName,
      'status': BookingStatus.technicianAssigned.name,
    });
    await _firestore.collection('notifications').add({
      'userId': technicianId,
      'title': 'New Assignment',
      'body': 'You have a new service booking.',
      'bookingId': bookingId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }
}
