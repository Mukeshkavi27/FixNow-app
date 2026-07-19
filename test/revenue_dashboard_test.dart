import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/presentation/revenue_dashboard.dart';
import 'package:flutter/material.dart';
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

  Booking booking(String id, BranchInfo branch, String service) => Booking(
        id: id,
        customerId: 'customer-$id',
        customerName: 'Customer $id',
        phone: '9999999999',
        address: branch.city,
        applianceType: service,
        problemDescription: 'Repair',
        preferredDate: now,
        preferredTime: '10:00 AM',
        status: BookingStatus.closed,
        createdAt: now,
        branchId: branch.id,
        branchName: branch.name,
      );

  testWidgets('renders revenue cards, charts, reports, and branch filter',
      (tester) async {
    final bookings = [
      booking('one', chennai, 'Air Conditioner'),
      booking('two', bengaluru, 'Washing Machine'),
    ];
    final bills = [
      Bill(
        id: 'one',
        bookingId: 'one',
        customerId: 'customer-one',
        technicianId: 'tech-one',
        amount: 1200,
        createdAt: now,
        paidAt: now,
        isPaid: true,
        branchId: chennai.id,
      ),
      Bill(
        id: 'two',
        bookingId: 'two',
        customerId: 'customer-two',
        technicianId: 'tech-two',
        amount: 800,
        createdAt: now,
        paidAt: now,
        isPaid: true,
        branchId: bengaluru.id,
      ),
    ];
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: RevenueDashboard(
              bills: bills,
              bookings: bookings,
              branches: const [chennai, bengaluru],
              technicians: const [],
              now: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Daily revenue',
      'Weekly revenue',
      'Monthly revenue',
      'Yearly revenue',
      'Branch-wise revenue',
      'Technician revenue',
      'Service revenue',
      'Revenue reports',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('₹2,000'), findsWidgets);

    await tester.tap(find.text('All branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FixNow Chennai').last);
    await tester.pumpAndSettle();

    expect(find.text('₹1,200'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
