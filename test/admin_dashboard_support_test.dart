import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/admin/presentation/admin_dashboard_support.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/technician/domain/technician_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filterAdminBookings keeps urgent assigned jobs first', () {
    final now = DateTime(2026, 6, 19, 12);
    final overdue = _booking(
      id: '1',
      appliance: 'Air Conditioner',
      customer: 'Asha',
      status: BookingStatus.technicianAssigned,
      date: DateTime(2026, 6, 19),
      time: '08:00 AM',
      technicianId: 'tech-1',
    );
    final later = _booking(
      id: '2',
      appliance: 'Microwave',
      customer: 'Bala',
      status: BookingStatus.booked,
      date: DateTime(2026, 6, 19),
      time: '05:00 PM',
    );

    final result = filterAdminBookings(
      bookings: [later, overdue],
      now: now,
      range: AdminRangeFilter.today,
    );

    expect(result.first.id, '1');
    expect(isBookingOverdue(overdue, now), isTrue);
  });

  test('buildTechnicianPerformance aggregates daily and monthly earnings', () {
    final now = DateTime(2026, 6, 19, 12);
    final technician = AppUser(
      uid: 'tech-1',
      name: 'Ravi',
      email: 'ravi@test.com',
      phone: '1234567890',
      role: UserRole.technician,
      createdAt: now,
      isActive: true,
    );
    final performance = buildTechnicianPerformance(
      technicians: [technician],
      bills: [
        Bill(
          id: 'b1',
          bookingId: 'bk1',
          customerId: 'c1',
          technicianId: 'tech-1',
          amount: 500,
          createdAt: now,
          isPaid: true,
        ),
        Bill(
          id: 'b2',
          bookingId: 'bk2',
          customerId: 'c2',
          technicianId: 'tech-1',
          amount: 300,
          createdAt: now.subtract(const Duration(days: 2)),
          isPaid: false,
        ),
      ],
      bookings: [
        _booking(
          id: 'bk1',
          appliance: 'Air Conditioner',
          customer: 'Asha',
          status: BookingStatus.accepted,
          date: DateTime(2026, 6, 19),
          time: '01:00 PM',
          technicianId: 'tech-1',
        ),
      ],
      locations: [
        TechnicianLocation(
          technicianId: 'tech-1',
          latitude: 12.0,
          longitude: 77.0,
          updatedAt: now,
          activeBookingId: 'bk1',
        ),
      ],
      now: now,
    );

    expect(performance.single.dailyEarnings, 500);
    expect(performance.single.monthlyEarnings, 500);
    expect(performance.single.lifetimeCollections, 500);
    expect(performance.single.pendingCollections, 300);
    expect(performance.single.activeBookings, 1);
  });
}

Booking _booking({
  required String id,
  required String appliance,
  required String customer,
  required BookingStatus status,
  required DateTime date,
  required String time,
  String? technicianId,
}) {
  return Booking(
    id: id,
    customerId: 'customer-1',
    customerName: customer,
    phone: '1234567890',
    address: 'Main street',
    applianceType: appliance,
    problemDescription: 'Needs support',
    preferredDate: date,
    preferredTime: time,
    status: status,
    createdAt: date,
    technicianId: technicianId,
    technicianName: technicianId == null ? null : 'Ravi',
  );
}
