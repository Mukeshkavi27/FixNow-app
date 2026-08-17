import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/booking_status.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/booking.dart';

void validateBookingBranch(Booking booking) {
  final branchId = booking.branchId?.trim() ?? '';
  final branchName = booking.branchName?.trim() ?? '';
  if (branchId.isEmpty || branchName.isEmpty) {
    throw ArgumentError(
      'A valid branch must be assigned before creating a booking.',
    );
  }
}

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
  BookingStatus.workCompletedPendingCustomer,
};

bool isTechnicianBusyStatus(BookingStatus status) {
  return technicianBusyStatuses.contains(status);
}

Booking? findTechnicianActiveBooking(
  Iterable<Booking> bookings,
  String technicianId, {
  String? excludingBookingId,
}) {
  for (final booking in bookings) {
    if (booking.id != excludingBookingId &&
        booking.technicianId == technicianId &&
        isTechnicianBusyStatus(booking.status)) {
      return booking;
    }
  }
  return null;
}

bool isTechnicianVisibleStatus(BookingStatus status) {
  // Closed jobs are retained for the technician's completed-work history.
  // Only unassigned bookings are irrelevant to the technician dashboard.
  return status != BookingStatus.booked;
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
    validateBookingBranch(booking);
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

  Future<void> attachCustomerImage({
    required String bookingId,
    required String imageUrl,
  }) {
    return _firestore.collection('bookings').doc(bookingId).update({
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    final workloadRef =
        _firestore.collection('technician_active_jobs').doc(technicianId);
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
      if (!isTechnicianBusyStatus(next)) {
        transaction.delete(workloadRef);
      }
    });
  }

  Future<void> markTechnicianReachedCustomer({
    required String bookingId,
    required String technicianId,
    double? technicianLatitude,
    double? technicianLongitude,
    double? distanceFromCustomerMeters,
    bool manualOverride = false,
  }) {
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
      if (current != BookingStatus.onTheWay) {
        throw StateError('This booking is not currently on the way.');
      }
      final update = <String, dynamic>{
        'status': BookingStatus.arrived.name,
        'technicianReachedAt': FieldValue.serverTimestamp(),
        'technicianReachedByManualOverride': manualOverride,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (technicianLatitude != null && technicianLongitude != null) {
        update['technicianReachedLatitude'] = technicianLatitude;
        update['technicianReachedLongitude'] = technicianLongitude;
      }
      if (distanceFromCustomerMeters != null) {
        update['technicianArrivalDistanceMeters'] = distanceFromCustomerMeters;
      }
      transaction.update(bookingRef, update);
    }).then((_) async {
      final snapshot = await bookingRef.get();
      final data = snapshot.data();
      if (data == null) return;
      await _createNotificationBestEffort({
        'userId': data['customerId'],
        'bookingId': bookingId,
        'type': 'technicianReachedCustomer',
        'title': 'Technician has arrived',
        'body':
            '${data['technicianName'] ?? 'Your technician'} has reached your service location.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _createNotificationBestEffort({
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
    double? customerLatitude,
    double? customerLongitude,
    double? technicianLatitude,
    double? technicianLongitude,
    double? maxDistanceMeters,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
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
      if (current != BookingStatus.arrived &&
          current != BookingStatus.onTheWay) {
        throw StateError('Technician arrival is not ready for confirmation.');
      }
      final technicianId = data['technicianId'] as String?;
      if (technicianId == null || technicianId.isEmpty) {
        throw StateError('No technician is assigned to this booking.');
      }
      final distanceMeters = customerLatitude == null ||
              customerLongitude == null ||
              technicianLatitude == null ||
              technicianLongitude == null
          ? null
          : _distanceMeters(
              customerLatitude,
              customerLongitude,
              technicianLatitude,
              technicianLongitude,
            );
      final update = <String, dynamic>{
        'status': BookingStatus.customerConfirmedArrival.name,
        'customerConfirmedArrivalAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (customerLatitude != null && customerLongitude != null) {
        update['customerConfirmedLatitude'] = customerLatitude;
        update['customerConfirmedLongitude'] = customerLongitude;
      }
      if (distanceMeters != null) {
        update['customerTechnicianDistanceMeters'] = distanceMeters;
        if (maxDistanceMeters != null && distanceMeters > maxDistanceMeters) {
          update['customerConfirmationDistanceWarning'] = true;
        }
      }
      transaction.update(bookingRef, update);
    }).then((_) async {
      final snapshot = await bookingRef.get();
      final data = snapshot.data();
      if (data == null) return;
      final technicianId = data['technicianId'] as String?;
      if (technicianId == null || technicianId.isEmpty) return;
      await _createNotificationBestEffort({
        'userId': technicianId,
        'bookingId': bookingId,
        'type': 'customerArrivalConfirmed',
        'title': 'Customer confirmed arrival',
        'body':
            '${data['customerName'] ?? 'Customer'} confirmed that you reached the service location.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _createNotificationBestEffort({
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

  Future<void> _createNotificationBestEffort(Map<String, dynamic> data) async {
    try {
      await _firestore.collection('notifications').add(data);
    } catch (_) {
      // Notifications must not block the booking state machine.
    }
  }

  Future<void> confirmWorkCompleted({
    required String bookingId,
    required String customerId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId) {
        throw StateError('You can only confirm your own booking.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      final alreadyConfirmed = data['customerConfirmedWorkCompletedAt'] != null;
      if (current == BookingStatus.serviceCompleted && alreadyConfirmed) {
        throw StateError('Work completion is already confirmed.');
      }
      if (current != BookingStatus.workCompletedPendingCustomer &&
          current != BookingStatus.serviceCompleted) {
        throw StateError('Work completion is not ready for confirmation.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.serviceCompleted.name,
        'customerConfirmedWorkCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final technicianId = data['technicianId'] as String?;
      if (technicianId != null && technicianId.isNotEmpty) {
        final lockRef =
            _firestore.collection('technician_active_jobs').doc(technicianId);
        // This customer has no permission to read a technician's lock. The
        // Firestore rule verifies that this exact lock belongs to this booking
        // and is being released alongside the completion confirmation.
        transaction.delete(lockRef);
      }
    }).then((_) async {
      final snapshot = await bookingRef.get();
      final data = snapshot.data();
      if (data == null) return;
      final technicianId = data['technicianId'] as String?;
      if (technicianId != null && technicianId.isNotEmpty) {
        await _createNotificationBestEffort({
          'userId': technicianId,
          'bookingId': bookingId,
          'type': 'customerWorkCompletedConfirmed',
          'title': 'Customer confirmed completion',
          'body':
              '${data['customerName'] ?? 'Customer'} confirmed the work is completed. You can generate the bill now.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await _createNotificationBestEffort({
        'userId': 'admin',
        'bookingId': bookingId,
        'type': 'customerWorkCompletedConfirmed',
        'title': 'Work completion confirmed',
        'body':
            '${data['customerName'] ?? 'Customer'} confirmed ${data['applianceType'] ?? 'service'} work is completed.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reportWorkNotDone({
    required String bookingId,
    required String customerId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['customerId'] != customerId) {
        throw StateError('You can only report your own booking.');
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current != BookingStatus.workCompletedPendingCustomer) {
        throw StateError('Work completion report is not available now.');
      }
      transaction.update(bookingRef, {
        'customerReportedWorkNotDoneAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).then((_) async {
      final snapshot = await bookingRef.get();
      final data = snapshot.data();
      if (data == null) return;
      await _createNotificationBestEffort({
        'userId': 'admin',
        'bookingId': bookingId,
        'type': 'customerReportedWorkNotDone',
        'title': 'Customer says work is not done',
        'body':
            '${data['customerName'] ?? 'Customer'} says ${data['applianceType'] ?? 'service'} work is not completed yet.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> requestWorkCompletion({
    required String bookingId,
    required String technicianId,
  }) {
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
      final customerConfirmed =
          data['customerConfirmedWorkCompletedAt'] != null;
      if (current != BookingStatus.serviceStarted &&
          !(current == BookingStatus.serviceCompleted && !customerConfirmed)) {
        throw StateError('Work completion cannot be requested now.');
      }
      transaction.update(bookingRef, {
        'status': BookingStatus.workCompletedPendingCustomer.name,
        'technicianCompletedWorkAt': FieldValue.serverTimestamp(),
        'customerReportedWorkNotDoneAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).then((_) async {
      final snapshot = await bookingRef.get();
      final data = snapshot.data();
      if (data == null) return;
      await _createNotificationBestEffort({
        'userId': data['customerId'],
        'bookingId': bookingId,
        'type': 'workCompletionRequested',
        'title': 'Technician confirmed completion',
        'body':
            '${data['technicianName'] ?? 'Your technician'} confirmed the service is completed. Please confirm from your side after checking the appliance.',
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
      if (current != BookingStatus.arrived &&
          current != BookingStatus.onTheWay) {
        throw StateError('Arrival report is not available now.');
      }
      transaction.update(bookingRef, {
        'customerReportedNotMetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(adminNotificationRef, {
        'userId': 'branch:${data['branchId']}',
        'recipientRole': 'branchAdmin',
        'branchId': data['branchId'],
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
    final bookingSnapshot = await bookingRef.get();
    final bookingData = bookingSnapshot.data();
    if (bookingData == null) throw StateError('Booking not found.');
    final originalBranchId = bookingData['branchId'] as String? ?? '';
    if (originalBranchId.isEmpty) {
      throw StateError(
          'The booking must belong to a branch before assignment.');
    }

    final assignedSnapshot = await _firestore
        .collection('bookings')
        .where('branchId', isEqualTo: originalBranchId)
        .where('technicianId', isEqualTo: technicianId)
        .get();
    final existingActiveBooking = findTechnicianActiveBooking(
      assignedSnapshot.docs.map(Booking.fromFirestore),
      technicianId,
      excludingBookingId: bookingId,
    );
    if (existingActiveBooking != null) {
      throw StateError(
        'This technician already has an active job. It must be completed, or the technician must place it on hold, before another assignment.',
      );
    }

    final workloadRef =
        _firestore.collection('technician_active_jobs').doc(technicianId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      final technicianRef = _firestore.collection('users').doc(technicianId);
      final technicianSnapshot = await transaction.get(technicianRef);
      final workloadSnapshot = await transaction.get(workloadRef);
      final technician = technicianSnapshot.data();
      if (technician == null ||
          technician['role'] != 'technician' ||
          technician['isActive'] != true ||
          technician['accountStatus'] != 'approved') {
        throw StateError(
          'Technician must be active and approved.',
        );
      }
      final technicianBranchId = technician['branchId'] as String? ?? '';
      if (technicianBranchId != data['branchId']) {
        throw StateError(
          'Technician must be assigned to the booking branch.',
        );
      }
      final current =
          BookingStatus.fromString(data['status'] as String? ?? 'booked');
      if (current == BookingStatus.closed ||
          current == BookingStatus.serviceCompleted ||
          current == BookingStatus.billGenerated) {
        throw StateError('Completed bookings cannot be assigned.');
      }
      if (current != BookingStatus.booked && current != BookingStatus.onHold) {
        throw StateError(
          'This booking is already in progress. The assigned technician must place it on hold before reassignment.',
        );
      }

      final lockedBookingId = workloadSnapshot.data()?['bookingId'] as String?;
      if (lockedBookingId != null &&
          lockedBookingId.isNotEmpty &&
          lockedBookingId != bookingId) {
        final lockedBookingSnapshot = await transaction.get(
          _firestore.collection('bookings').doc(lockedBookingId),
        );
        final lockedBooking = lockedBookingSnapshot.data();
        final lockedStatus = BookingStatus.fromString(
          lockedBooking?['status'] as String? ?? BookingStatus.closed.name,
        );
        if (lockedBooking?['technicianId'] == technicianId &&
            isTechnicianBusyStatus(lockedStatus)) {
          throw StateError(
            'This technician already has an active job. It must be completed, or the technician must place it on hold, before another assignment.',
          );
        }
      }

      transaction.update(bookingRef, {
        'technicianId': technicianId,
        'technicianName': technicianName,
        'status': BookingStatus.technicianAssigned.name,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignmentUpdatedAt': FieldValue.serverTimestamp(),
        'holdReason': FieldValue.delete(),
        'heldAt': FieldValue.delete(),
        'heldFromStatus': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(workloadRef, {
        'technicianId': technicianId,
        'bookingId': bookingId,
        'branchId': data['branchId'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    // Notification policy must never roll back the operational assignment.
    // Firestore/Sockets already deliver the booking itself in real time.
    try {
      await _firestore.collection('notifications').add({
        'userId': technicianId,
        'bookingId': bookingId,
        'branchId': originalBranchId,
        'type': 'technicianAssignment',
        'title': 'New service assigned',
        'body':
            '${bookingData['applianceType'] ?? 'Service'} for ${bookingData['customerName'] ?? 'customer'} is assigned to you.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // Socket.IO bookingAssigned and the technician booking snapshot remain
      // authoritative when optional notification creation is restricted.
    }
  }

  Future<void> rejectAssignment({
    required String bookingId,
    required String technicianId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final workloadRef =
        _firestore.collection('technician_active_jobs').doc(technicianId);
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
        'heldFromStatus': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(workloadRef);
    });
  }

  Future<void> placeOnHold({
    required String bookingId,
    required String actingTechnicianId,
    required String reason,
  }) {
    final holdReason = reason.trim();
    if (holdReason.isEmpty) {
      throw ArgumentError('Hold reason is required.');
    }
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
    final customerNotificationRef =
        _firestore.collection('notifications').doc();
    final adminNotificationRef = _firestore.collection('notifications').doc();
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(bookingRef);
      final data = snapshot.data();
      if (data == null) throw StateError('Booking not found.');
      if (data['technicianId'] != actingTechnicianId) {
        throw StateError(
            'Only the assigned technician can place this job on hold.');
      }
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
        // Keep the exact workflow stage so resuming does not skip a required
        // customer or technician confirmation.
        'heldFromStatus': current.name,
        'heldAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final technicianId = data['technicianId'] as String?;
      if (technicianId != null && technicianId.isNotEmpty) {
        transaction.delete(
          _firestore.collection('technician_active_jobs').doc(technicianId),
        );
      }
      transaction.set(customerNotificationRef, {
        'userId': data['customerId'],
        'bookingId': bookingId,
        'type': 'bookingOnHold',
        'title': 'Service temporarily on hold',
        'body':
            'Reason: $holdReason. Your technician will resume the service as soon as possible.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final branchId = data['branchId'] as String?;
      if (branchId != null && branchId.isNotEmpty) {
        transaction.set(adminNotificationRef, {
          'userId': 'branch:$branchId',
          'recipientRole': 'branchAdmin',
          'technicianId': actingTechnicianId,
          'branchId': branchId,
          'bookingId': bookingId,
          'type': 'bookingOnHold',
          'title': 'Technician placed a job on hold',
          'body': '${data['technicianName'] ?? 'The assigned technician'} '
              'placed ${data['serviceType'] ?? 'the service'} on hold. '
              'Reason: $holdReason',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> resumeFromHold({
    required String bookingId,
    required String actingTechnicianId,
  }) {
    final bookingRef = _firestore.collection('bookings').doc(bookingId);
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
      if (technicianId != actingTechnicianId) {
        throw StateError('Only the assigned technician can resume this job.');
      }
      final resumeStatus = BookingStatus.fromString(
        data['heldFromStatus'] as String? ?? BookingStatus.serviceStarted.name,
      );
      if (!isTechnicianBusyStatus(resumeStatus)) {
        throw StateError('This booking cannot be resumed at its saved stage.');
      }
      final workloadRef =
          _firestore.collection('technician_active_jobs').doc(technicianId);
      final workload = await transaction.get(workloadRef);
      final lockedBookingId = workload.data()?['bookingId'] as String?;
      if (lockedBookingId != null &&
          lockedBookingId.isNotEmpty &&
          lockedBookingId != bookingId) {
        final lockedBooking = await transaction.get(
          _firestore.collection('bookings').doc(lockedBookingId),
        );
        final lockedData = lockedBooking.data();
        final lockedStatus = BookingStatus.fromString(
          lockedData?['status'] as String? ?? BookingStatus.closed.name,
        );
        if (lockedData?['technicianId'] == technicianId &&
            isTechnicianBusyStatus(lockedStatus)) {
          throw StateError(
            'This technician already has another active job.',
          );
        }
      }
      transaction.update(bookingRef, {
        'status': resumeStatus.name,
        'holdReason': FieldValue.delete(),
        'heldAt': FieldValue.delete(),
        'heldFromStatus': FieldValue.delete(),
        'resumedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(workloadRef, {
        'technicianId': technicianId,
        'bookingId': bookingId,
        'branchId': data['branchId'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(customerNotificationRef, {
        'userId': data['customerId'],
        'bookingId': bookingId,
        'branchId': data['branchId'],
        'type': 'bookingResumed',
        'title': 'Service resumed',
        'body': 'Your FixNow service has been resumed.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

double _distanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = latitudeA * math.pi / 180;
  final lat2 = latitudeB * math.pi / 180;
  final deltaLat = (latitudeB - latitudeA) * math.pi / 180;
  final deltaLng = (longitudeB - longitudeA) * math.pi / 180;
  final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}
