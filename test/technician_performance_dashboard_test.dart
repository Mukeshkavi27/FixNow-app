import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/review.dart';
import 'package:fixnow/features/shared/presentation/technician_performance_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 14);
  const branch = BranchInfo(
    id: 'branch-a',
    name: 'FixNow Chennai',
    city: 'Chennai',
    latitude: 13.08,
    longitude: 80.27,
  );
  final technician = AppUser(
    uid: 'tech-1',
    name: 'Ravi Kumar',
    email: 'ravi@test.dev',
    phone: '9999999999',
    role: UserRole.technician,
    accountStatus: AccountStatus.approved,
    branchId: branch.id,
    branchName: branch.name,
    createdAt: now,
    isActive: true,
  );
  final booking = Booking(
    id: 'booking-1',
    customerId: 'customer-1',
    customerName: 'Customer',
    phone: '9999999998',
    address: 'Chennai',
    applianceType: 'AC',
    problemDescription: 'Service',
    preferredDate: now,
    preferredTime: '10:00 AM',
    status: BookingStatus.closed,
    createdAt: now,
    technicianId: technician.uid,
    branchId: branch.id,
    branchName: branch.name,
  );

  testWidgets('renders every required technician performance surface',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: TechnicianPerformanceDashboard(
              technicians: [technician],
              bookings: [booking],
              bills: [
                Bill(
                  id: booking.id,
                  bookingId: booking.id,
                  customerId: booking.customerId,
                  technicianId: technician.uid,
                  branchId: branch.id,
                  amount: 2500,
                  createdAt: now,
                  paidAt: now,
                  isPaid: true,
                ),
              ],
              reviews: [
                Review(
                  id: booking.id,
                  bookingId: booking.id,
                  technicianId: technician.uid,
                  customerId: booking.customerId,
                  branchId: branch.id,
                  rating: 5,
                  text: 'Excellent',
                  createdAt: now,
                ),
              ],
              branches: const [branch],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Technician revenue',
      'Jobs completed',
      'Average rating',
      'Completion rate',
      'Customer satisfaction',
      'Top performers',
      'Lowest performers',
      'Technician leaderboard',
      'Branch ranking',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.text('₹2,500'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
