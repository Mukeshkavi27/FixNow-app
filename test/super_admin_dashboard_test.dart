import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/super_admin/domain/audit_log_entry.dart';
import 'package:fixnow/features/super_admin/presentation/super_admin_dashboard_screen.dart';
import 'package:fixnow/features/technician/domain/overtime_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 13, 10);
  final superAdmin = AppUser(
    uid: 'super-1',
    name: 'FixNow Owner',
    email: 'owner@fixnow.test',
    phone: '9999999999',
    role: UserRole.superAdmin,
    accountStatus: AccountStatus.approved,
    createdAt: now,
    isActive: true,
  );
  const branch = BranchInfo(
    id: 'branch-a',
    name: 'FixNow Chennai',
    city: 'Chennai',
    latitude: 13.08,
    longitude: 80.27,
    isActive: true,
  );
  final technician = AppUser(
    uid: 'tech-1',
    name: 'Ravi Technician',
    email: 'ravi@fixnow.test',
    phone: '9999999998',
    role: UserRole.technician,
    branchId: branch.id,
    branchName: branch.name,
    createdAt: now,
    isActive: true,
  );
  final customer = AppUser(
    uid: 'customer-1',
    name: 'Asha Customer',
    email: 'asha@fixnow.test',
    phone: '9999999997',
    role: UserRole.customer,
    branchId: branch.id,
    branchName: branch.name,
    createdAt: now,
    isActive: true,
  );
  final branchAdmin = AppUser(
    uid: 'branch-admin-1',
    name: 'Chennai Manager',
    email: 'manager@fixnow.test',
    phone: '9999999996',
    role: UserRole.branchAdmin,
    accountStatus: AccountStatus.approved,
    branchId: branch.id,
    branchName: branch.name,
    createdAt: now,
    isActive: true,
  );
  final booking = Booking(
    id: 'booking-1',
    customerId: 'customer-1',
    customerName: 'Asha Customer',
    phone: '9999999997',
    address: 'Chennai',
    applianceType: 'Air Conditioner',
    problemDescription: 'Not cooling',
    preferredDate: now,
    preferredTime: '10:00 AM',
    status: BookingStatus.closed,
    createdAt: now,
    branchId: branch.id,
    branchName: branch.name,
    technicianId: technician.uid,
    technicianName: technician.name,
  );

  Widget dashboard({
    SuperAdminSection initialSection = SuperAdminSection.overview,
    ValueChanged<AppUser>? onTransferBranchAdmin,
    List<OvertimeRecord> overtimeRecords = const [],
    List<BranchInfo>? branchRecords,
    List<Booking>? bookingRecords,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: SuperAdminDashboardView(
        currentUser: superAdmin,
        branches: branchRecords ?? const [branch],
        bookings: bookingRecords ?? [booking],
        technicians: [technician],
        customers: [customer],
        branchAdmins: [branchAdmin],
        bills: [
          Bill(
            id: 'booking-1',
            bookingId: 'booking-1',
            customerId: 'customer-1',
            technicianId: 'tech-1',
            amount: 1200,
            createdAt: now,
            isPaid: true,
            branchId: branch.id,
          ),
        ],
        reviews: const [],
        auditLogs: [
          AuditLogEntry(
            id: 'audit-1',
            actorId: superAdmin.uid,
            actorRole: UserRole.superAdmin.name,
            action: 'branch.created',
            targetType: 'branch',
            targetId: branch.id,
            summary: 'Created FixNow Chennai',
            createdAt: now,
            branchId: branch.id,
          ),
        ],
        overtimeRecords: overtimeRecords,
        initialSection: initialSection,
        onTransferBranchAdmin: onTransferBranchAdmin,
      ),
    );
  }

  testWidgets('renders the responsive Super Admin overview on desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Super Admin Console'), findsOneWidget);
    expect(find.text('System overview'), findsOneWidget);
    expect(find.text('₹1,200'), findsWidgets);
    expect(find.text('Branch performance'), findsOneWidget);
  });

  testWidgets('renders without overflow on a narrow mobile viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('System overview'), findsOneWidget);
    expect(find.text('Bookings'), findsWidgets);
  });

  testWidgets('mobile bookings use readable cards instead of a wide table',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(initialSection: SuperAdminSection.bookings),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Asha Customer'), findsOneWidget);
    expect(find.text('Air Conditioner'), findsOneWidget);
    expect(find.textContaining('Ravi Technician'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Branch Admin actions stack without mobile overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(initialSection: SuperAdminSection.people),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chennai Manager'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin can filter all bookings by branch', (tester) async {
    const bengaluru = BranchInfo(
      id: 'branch-b',
      name: 'FixNow Bengaluru',
      city: 'Bengaluru',
      latitude: 12.97,
      longitude: 77.59,
      isActive: true,
    );
    final bengaluruBooking = Booking(
      id: 'booking-2',
      customerId: 'customer-2',
      customerName: 'Bengaluru Customer',
      phone: '9999999995',
      address: 'Indiranagar, Bengaluru',
      applianceType: 'Washing Machine',
      problemDescription: 'Drum not rotating',
      preferredDate: now,
      preferredTime: '12:00 PM',
      status: BookingStatus.booked,
      createdAt: now.add(const Duration(minutes: 5)),
      branchId: bengaluru.id,
      branchName: bengaluru.name,
    );

    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(
        initialSection: SuperAdminSection.bookings,
        branchRecords: const [branch, bengaluru],
        bookingRecords: [booking, bengaluruBooking],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 records across all branches'), findsOneWidget);
    expect(find.text('Asha Customer'), findsOneWidget);
    expect(find.text('Bengaluru Customer'), findsOneWidget);

    await tester.tap(find.text('All branches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FixNow Bengaluru').last);
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 records'), findsOneWidget);
    expect(find.text('Bengaluru Customer'), findsOneWidget);
    expect(find.text('Asha Customer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin revenue dashboard exposes network analytics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(initialSection: SuperAdminSection.revenue),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revenue and analytics'), findsOneWidget);
    expect(find.text('Revenue branch'), findsOneWidget);
    expect(find.text('All branches'), findsOneWidget);
    expect(find.text('Daily revenue'), findsWidgets);
    expect(find.text('Yearly revenue'), findsOneWidget);
    expect(find.text('Branch-wise revenue'), findsOneWidget);
    expect(find.text('Revenue reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin performance exposes leaderboard and branch ranking',
      (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(initialSection: SuperAdminSection.performance),
    );
    await tester.pumpAndSettle();

    expect(find.text('Technician performance'), findsOneWidget);
    expect(find.text('Performance branch'), findsOneWidget);
    expect(find.text('All branches'), findsOneWidget);
    expect(find.text('Top performers'), findsOneWidget);
    expect(find.text('Lowest performers'), findsOneWidget);
    expect(find.text('Technician leaderboard'), findsOneWidget);
    expect(find.text('Branch ranking'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin is notified of network overtime', (tester) async {
    final overtime = OvertimeRecord(
      id: 'tech-1_2026-07-13',
      technicianId: technician.uid,
      branchId: branch.id,
      dateKey: '2026-07-13',
      startedAt: DateTime(2026, 7, 13, 22),
      lastDetectedAt: DateTime(2026, 7, 13, 23, 12),
      isActive: true,
      extraBookingIds: [booking.id],
    );
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard(overtimeRecords: [overtime]));
    await tester.pumpAndSettle();

    expect(find.text('Network overtime'), findsOneWidget);
    expect(find.text('WORKING OVERTIME'), findsOneWidget);
    expect(find.textContaining('Ravi Technician'), findsOneWidget);
  });

  testWidgets('branch dashboard shows all required operational metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(initialSection: SuperAdminSection.branches),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Branch management'), findsOneWidget);
    expect(find.text('Branch dashboard'), findsOneWidget);
    for (final label in [
      'Bookings',
      'Revenue',
      'Technicians',
      'Customers',
      'Completed',
      'Pending',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('1 Branch Admin(s) · Radius 35 km'), findsOneWidget);
  });

  testWidgets('Branch Admin transfer action is exposed to Super Admin', (
    tester,
  ) async {
    AppUser? selectedAdmin;
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(
        initialSection: SuperAdminSection.people,
        onTransferBranchAdmin: (admin) => selectedAdmin = admin,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transfer'), findsOneWidget);
    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(selectedAdmin?.uid, branchAdmin.uid);
  });
}
