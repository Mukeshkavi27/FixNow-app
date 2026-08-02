import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/revenue_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 14, 12);
  const chennai = BranchInfo(
    id: 'chennai',
    name: 'FixNow Chennai',
    city: 'Chennai',
    latitude: 13.08,
    longitude: 80.27,
  );
  const bengaluru = BranchInfo(
    id: 'bengaluru',
    name: 'FixNow Bengaluru',
    city: 'Bengaluru',
    latitude: 12.97,
    longitude: 77.59,
  );
  final technicians = [
    AppUser(
      uid: 'tech-1',
      name: 'Ravi',
      email: 'ravi@test.dev',
      phone: '9999999999',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      branchId: chennai.id,
      createdAt: now,
      isActive: true,
    ),
    AppUser(
      uid: 'tech-2',
      name: 'Meena',
      email: 'meena@test.dev',
      phone: '9999999998',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      branchId: chennai.id,
      createdAt: now,
      isActive: true,
    ),
  ];

  Booking booking(String id, String service, BranchInfo branch) => Booking(
        id: id,
        customerId: 'customer-$id',
        customerName: 'Customer $id',
        phone: '9999999997',
        address: branch.city,
        applianceType: service,
        problemDescription: 'Service',
        preferredDate: now,
        preferredTime: '10:00 AM',
        status: BookingStatus.closed,
        createdAt: now,
        branchId: branch.id,
        branchName: branch.name,
      );

  Bill bill(
    String id,
    double amount,
    DateTime revenueDate, {
    String branchId = 'chennai',
    String technicianId = 'tech-1',
    bool paid = true,
  }) =>
      Bill(
        id: id,
        bookingId: id,
        customerId: 'customer-$id',
        technicianId: technicianId,
        amount: amount,
        createdAt: DateTime(2025, 1, 1),
        paidAt: revenueDate,
        isPaid: paid,
        branchId: branchId,
      );

  final bookings = [
    booking('today', 'Air Conditioner', chennai),
    booking('monday', 'Washing Machine', chennai),
    booking('month', 'Air Conditioner', chennai),
    booking('year', 'Refrigerator', chennai),
    booking('previous', 'Air Conditioner', chennai),
    booking('other', 'Washing Machine', bengaluru),
    booking('pending', 'Air Conditioner', chennai),
  ];
  final bills = [
    bill('today', 1000, DateTime(2026, 7, 14, 9)),
    bill('monday', 500, DateTime(2026, 7, 13, 16)),
    bill('month', 2000, DateTime(2026, 7, 1), technicianId: 'tech-2'),
    bill('year', 3000, DateTime(2026, 1, 10), technicianId: 'tech-2'),
    bill('previous', 4000, DateTime(2025, 12, 20)),
    bill(
      'other',
      900,
      DateTime(2026, 7, 14),
      branchId: 'bengaluru',
    ),
    bill('pending', 700, DateTime(2026, 7, 14), paid: false),
  ];

  test('calculates every revenue period from the confirmed payment date', () {
    final analytics = RevenueAnalytics.calculate(
      bills: bills,
      bookings: bookings,
      branches: const [chennai, bengaluru],
      technicians: technicians,
      now: now,
    );

    expect(analytics.today, 1900);
    expect(analytics.week, 2400);
    expect(analytics.month, 4400);
    expect(analytics.year, 7400);
    expect(analytics.allTime, 11400);
    expect(analytics.pendingAmount, 700);
    expect(analytics.paidBillCount, 6);
    expect(analytics.dailyTrend.length, 7);
    expect(analytics.monthlyTrend.length, 12);
  });

  test('branch scope and all revenue breakdowns preserve relationships', () {
    final analytics = RevenueAnalytics.calculate(
      bills: bills,
      bookings: bookings,
      branches: const [chennai, bengaluru],
      technicians: technicians,
      now: now,
      branchId: chennai.id,
    );

    expect(analytics.today, 1000);
    expect(analytics.allTime, 10500);
    expect(analytics.branchRevenue.single.label, chennai.name);
    expect(analytics.technicianRevenue.first.label, 'Ravi');
    expect(analytics.serviceRevenue.first.label, 'Air Conditioner');
    expect(analytics.serviceRevenue.first.amount, 7000);
    expect(
        analytics.reportRows.map((row) => row.period), contains('This year'));
  });

  test('transferred technician revenue remains with the native branch', () {
    final transferred = AppUser(
      uid: 'transferred-tech',
      name: 'Native Chennai Technician',
      email: 'transfer@test.dev',
      phone: '9999999996',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      branchId: bengaluru.id,
      branchName: bengaluru.name,
      nativeBranchId: chennai.id,
      nativeBranchName: chennai.name,
      createdAt: now,
      isActive: true,
    );
    final transferredBill = Bill(
      id: 'transferred-job',
      bookingId: 'transferred-job',
      customerId: 'customer-transfer',
      technicianId: transferred.uid,
      amount: 2500,
      createdAt: now,
      paidAt: now,
      isPaid: true,
      branchId: bengaluru.id,
      revenueBranchId: chennai.id,
    );
    final chennaiRevenue = RevenueAnalytics.calculate(
      bills: [transferredBill],
      bookings: const [],
      branches: const [chennai, bengaluru],
      technicians: [transferred],
      now: now,
      branchId: chennai.id,
    );
    final bengaluruRevenue = RevenueAnalytics.calculate(
      bills: [transferredBill],
      bookings: const [],
      branches: const [chennai, bengaluru],
      technicians: [transferred],
      now: now,
      branchId: bengaluru.id,
    );

    expect(chennaiRevenue.allTime, 2500);
    expect(chennaiRevenue.technicianRevenue.single.label,
        'Native Chennai Technician');
    expect(bengaluruRevenue.allTime, 0);
  });
}
