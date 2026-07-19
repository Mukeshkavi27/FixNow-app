import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/features/bookings/data/booking_repository.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Booking booking({String? branchId, String? branchName}) {
    final now = DateTime(2026, 7, 14);
    return Booking(
      id: 'booking-1',
      customerId: 'customer-1',
      customerName: 'Customer',
      phone: '9999999999',
      address: 'Address',
      applianceType: 'AC',
      problemDescription: 'Not cooling',
      preferredDate: now,
      preferredTime: '10:00 AM',
      status: BookingStatus.booked,
      createdAt: now,
      branchId: branchId,
      branchName: branchName,
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
}
