import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/technician/domain/overtime_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overtime starts at 10 PM and ends at midnight', () {
    expect(isTechnicianOvertime(DateTime(2026, 7, 14, 21, 59, 59)), isFalse);
    expect(isTechnicianOvertime(DateTime(2026, 7, 14, 22)), isTrue);
    expect(isTechnicianOvertime(DateTime(2026, 7, 14, 23, 59)), isTrue);
    expect(isTechnicianOvertime(DateTime(2026, 7, 15)), isFalse);
  });

  test('summary reports overtime duration, extra bookings, and paid revenue',
      () {
    final record = OvertimeRecord(
      id: 'tech-1_2026-07-14',
      technicianId: 'tech-1',
      branchId: 'branch-1',
      dateKey: '2026-07-14',
      startedAt: DateTime(2026, 7, 14, 22),
      lastDetectedAt: DateTime(2026, 7, 14, 23, 12),
      isActive: true,
      extraBookingIds: const ['booking-1'],
    );
    final booking = Booking(
      id: 'booking-1',
      customerId: 'customer-1',
      customerName: 'Asha',
      phone: '9000000000',
      address: 'Chennai',
      applianceType: 'AC',
      problemDescription: 'Not cooling',
      preferredDate: DateTime(2026, 7, 14),
      preferredTime: '10:00 PM',
      status: BookingStatus.closed,
      createdAt: DateTime(2026, 7, 14, 20),
      updatedAt: DateTime(2026, 7, 14, 22, 45),
      technicianId: 'tech-1',
    );
    final bill = Bill(
      id: 'booking-1',
      bookingId: 'booking-1',
      customerId: 'customer-1',
      technicianId: 'tech-1',
      amount: 1850,
      createdAt: DateTime(2026, 7, 14, 22, 45),
      isPaid: true,
    );

    final summary = summarizeOvertime(
      record: record,
      bookings: [booking],
      bills: [bill],
    );
    expect(summary.duration, const Duration(hours: 1, minutes: 12));
    expect(summary.extraBookings, 1);
    expect(summary.extraRevenue, 1850);
    expect(formatOvertimeDuration(summary.duration), '1h 12m');
  });
}
