import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/booking.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(firebaseRefsProvider).firestore);
});

const technicianBusyStatuses = {
  BookingStatus.technicianAssigned,
  BookingStatus.accepted,
  BookingStatus.onTheWay,
  BookingStatus.arrived,
  BookingStatus.customerConfirmedArrival,
  BookingStatus.estimateSent,
  BookingStatus.estimateRejected,
  BookingStatus.estimateApproved,
  BookingStatus.serviceStarted,
};

bool isTechnicianBusyStatus(BookingStatus status) {
  return technicianBusyStatuses.contains(status);
}

bool isTechnicianVisibleStatus(BookingStatus status) {
  return status != BookingStatus.booked && status != BookingStatus.closed;
}

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
        .map((snapshot) {
      final bookings = snapshot.docs
          .map(Booking.fromFirestore)
          .where((booking) => isTechnicianVisibleStatus(booking.status))
          .toList();
      return _sortNewestFirst(bookings);
    });
  }

  Stream<List<Booking>> watchAllBookings({String? branchId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('bookings');
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.orderBy('createdAt', descending: true).snapshots().map(
        (snapshot) => _sortNewestFirst(
            snapshot.docs.map(Booking.fromFirestore).toList()));
  }

  List<Booking> _sortNewestFirst(List<Booking> bookings) {
    bookings.sort((a, b) {
      final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
      if (updatedCompare != 0) return updatedCompare;
      return b.createdAt.compareTo(a.createdAt);
    });
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
    final data = {
      ...booking.toJson(),
      'status': BookingStatus.booked.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    data
      ..remove('technicianId')
      ..remove('technicianName')
      ..remove('holdReason')
      ..remove('heldAt');
    await doc.set(data);
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

  Future<void> markTechnicianReachedCustomer({
    required String bookingId,
    required String technicianId,
    bool manualOverride = false,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final customerNotificationRef =
        _firestore.collection('notifications').doc();
    final adminNotificationRef = _firestore.collection('notifications').doc();
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['technicianId'] != technicianId) {
        throw StateError('This booking is not assigned to this technician.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current != BookingStatus.onTheWay) {
        throw StateError('This booking is not currently on the way.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.arrived.name,
        'technicianReachedAt': FieldValue.serverTimestamp(),
        'technicianReachedByManualOverride': manualOverride,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(customerNotificationRef, {
        'userId': data['customerId'],
        'bookingId': bookingId,
        'type': 'technicianReachedCustomer',
        'title': 'Technician has arrived',
        'body':
            '${data['technicianName'] ?? 'Your technician'} has reached your service location.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(adminNotificationRef, {
        'userId': 'admin',
        'bookingId': bookingId,
        'type': 'technicianReachedCustomer',
        'title': manualOverride
            ? 'Technician used manual arrival'
            : 'Technician reached customer',
        'body':
            '${data['technicianName'] ?? 'Technician'} reached ${data['customerName'] ?? 'customer'} for ${data['applianceType'] ?? 'service'}.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> confirmTechnicianArrival({
    required String bookingId,
    required String customerId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final technicianNotificationRef =
        _firestore.collection('notifications').doc();
    final adminNotificationRef = _firestore.collection('notifications').doc();
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId) {
        throw StateError('You can only confirm your own booking.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current == BookingStatus.customerConfirmedArrival) {
        throw StateError('Arrival is already confirmed.');
      }
      if (current != BookingStatus.arrived) {
        throw StateError('Technician arrival is not ready for confirmation.');
      }
      final technicianId = data['technicianId'] as String?;
      if (technicianId == null || technicianId.isEmpty) {
        throw StateError('No technician is assigned to this booking.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.customerConfirmedArrival.name,
        'customerConfirmedArrivalAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(technicianNotificationRef, {
        'userId': technicianId,
        'bookingId': bookingId,
        'type': 'customerArrivalConfirmed',
        'title': 'Customer confirmed arrival',
        'body':
            '${data['customerName'] ?? 'Customer'} confirmed that you reached the service location.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(adminNotificationRef, {
        'userId': 'admin',
        'bookingId': bookingId,
        'type': 'customerArrivalConfirmed',
        'title': 'Technician arrival confirmed',
        'body':
            '${data['customerName'] ?? 'Customer'} confirmed ${data['technicianName'] ?? 'the technician'} reached ${data['applianceType'] ?? 'the service'} booking.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reportTechnicianNotMet({
    required String bookingId,
    required String customerId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final adminNotificationRef = _firestore.collection('notifications').doc();
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId) {
        throw StateError('You can only report your own booking.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current != BookingStatus.arrived) {
        throw StateError('Arrival report is not available now.');
      }
      transaction.update(bookingRef, {
        'customerReportedNotMetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(adminNotificationRef, {
        'userId': 'admin',
        'bookingId': bookingId,
        'type': 'customerReportedTechnicianNotMet',
        'title': 'Customer says technician not met',
        'body':
            '${data['customerName'] ?? 'Customer'} says ${data['technicianName'] ?? 'the technician'} has not met them yet.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
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
    final notificationRef = _firestore.collection('notifications').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current == BookingStatus.closed ||
          current == BookingStatus.serviceCompleted ||
          current == BookingStatus.billGenerated) {
        throw StateError('Completed bookings cannot be assigned.');
      }
      if (current != BookingStatus.booked && current != BookingStatus.onHold) {
        throw StateError(
          'This booking is already in progress. Put it on hold before assigning another technician.',
        );
      }
      transaction.update(bookingRef, {
        'technicianId': technicianId,
        'technicianName': technicianName,
        'status': BookingStatus.technicianAssigned.name,
        'holdReason': FieldValue.delete(),
        'heldAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'userId': technicianId,
        'bookingId': bookingId,
        'type': 'technicianAssignment',
        'title': 'New service assigned',
        'body':
            '${data['applianceType'] ?? 'Service'} for ${data['customerName'] ?? 'customer'} is assigned to you.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
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
        'holdReason': FieldValue.delete(),
        'heldAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> placeOnHold({
    required String bookingId,
    required String reason,
  }) {
    final holdReason = reason.trim();
    if (holdReason.isEmpty) {
      throw ArgumentError('Hold reason is required.');
    }
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current == BookingStatus.booked ||
          current == BookingStatus.onHold ||
          current == BookingStatus.serviceCompleted ||
          current == BookingStatus.billGenerated ||
          current == BookingStatus.closed) {
        throw StateError('This booking cannot be placed on hold now.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.onHold.name,
        'holdReason': holdReason,
        'heldAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> resumeFromHold({
    required String bookingId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final technicianNotificationRef =
        _firestore.collection('notifications').doc();
    final customerNotificationRef =
        _firestore.collection('notifications').doc();
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current != BookingStatus.onHold) {
        throw StateError('Only on-hold bookings can be resumed.');
      }
      final technicianId = data['technicianId'] as String?;
      if (technicianId == null || technicianId.isEmpty) {
        throw StateError('Assign a technician before resuming this booking.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.serviceStarted.name,
        'holdReason': FieldValue.delete(),
        'heldAt': FieldValue.delete(),
        'resumedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(technicianNotificationRef, {
        'userId': technicianId,
        'bookingId': bookingId,
        'type': 'bookingResumed',
        'title': 'Booking resumed',
        'body':
            '${data['applianceType'] ?? 'Service'} for ${data['customerName'] ?? 'customer'} has been resumed.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(customerNotificationRef, {
        'userId': data['customerId'],
        'bookingId': bookingId,
        'type': 'bookingResumed',
        'title': 'Service resumed',
        'body': 'Your FixNow service has been resumed.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
