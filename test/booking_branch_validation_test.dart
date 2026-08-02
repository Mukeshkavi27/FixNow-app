import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/features/bookings/data/booking_repository.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Booking booking({
    String id = 'booking-1',
    String? branchId,
    String? branchName,
    String? technicianId,
    BookingStatus status = BookingStatus.booked,
  }) {
    final now = DateTime(2026, 7, 14);
    return Booking(
      id: id,
      customerId: 'customer-1',
      customerName: 'Customer',
      phone: '9999999999',
      address: 'Address',
      applianceType: 'AC',
      problemDescription: 'Not cooling',
      preferredDate: now,
      preferredTime: '10:00 AM',
      status: status,
      createdAt: now,
      branchId: branchId,
      branchName: branchName,
      technicianId: technicianId,
    );
  }

  test('new bookings require both branch ID and branch name', () {
    expect(
      () => validateBookingBranch(booking()),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validateBookingBranch(
        booking(branchId: 'branch-a', branchName: '   '),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => validateBookingBranch(
        booking(branchId: 'branch-a', branchName: 'FixNow Chennai'),
      ),
      returnsNormally,
    );
  });

  test('technician can have only one active booking', () {
    final bookings = [
      booking(
        id: 'active',
        technicianId: 'tech-1',
        status: BookingStatus.onTheWay,
      ),
      booking(
        id: 'held',
        technicianId: 'tech-1',
        status: BookingStatus.onHold,
      ),
      booking(
        id: 'completed',
        technicianId: 'tech-1',
        status: BookingStatus.serviceCompleted,
      ),
    ];

    expect(
      findTechnicianActiveBooking(bookings, 'tech-1')?.id,
      'active',
    );
    expect(
      findTechnicianActiveBooking(
        bookings,
        'tech-1',
        excludingBookingId: 'active',
      ),
      isNull,
    );
    expect(findTechnicianActiveBooking(bookings, 'tech-2'), isNull);
  });
}
