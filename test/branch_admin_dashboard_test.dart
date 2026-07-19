import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/branches/branch_repository.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:fixnow/features/auth/data/auth_repository.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/review.dart';
import 'package:fixnow/features/shared/domain/app_notification.dart';
import 'package:fixnow/features/technician/domain/attendance.dart';
import 'package:fixnow/features/technician/domain/overtime_record.dart';
import 'package:fixnow/features/technician/domain/technician_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 13, 10, 30);
  const branch = BranchInfo(
    id: 'branch-chennai',
    name: 'FixNow Chennai',
    city: 'Chennai',
    latitude: 13.0827,
    longitude: 80.2707,
    isActive: true,
  );
  final branchAdmin = AppUser(
    uid: 'branch-admin-1',
    name: 'Chennai Manager',
    email: 'manager@fixnow.test',
    phone: '9999999999',
    role: UserRole.branchAdmin,
    accountStatus: AccountStatus.approved,
    createdAt: now,
    isActive: true,
    branchId: branch.id,
    branchName: branch.name,
  );
  final technician = AppUser(
    uid: 'tech-1',
    name: 'Ravi Kumar',
    email: 'ravi@fixnow.test',
    phone: '9999999998',
    role: UserRole.technician,
    accountStatus: AccountStatus.approved,
    createdAt: now,
    isActive: true,
    branchId: branch.id,
    branchName: branch.name,
  );
  final customer = AppUser(
    uid: 'customer-1',
    name: 'Asha',
    email: 'asha@fixnow.test',
    phone: '9999999997',
    role: UserRole.customer,
    createdAt: now,
    isActive: true,
    branchId: branch.id,
    branchName: branch.name,
  );
  final booking = Booking(
    id: 'booking-1',
    customerId: customer.uid,
    customerName: customer.name,
    phone: customer.phone,
    address: 'Anna Nagar, Chennai',
    applianceType: 'Air Conditioner',
    problemDescription: 'Not cooling',
    preferredDate: now,
    preferredTime: '11:00 AM',
    status: BookingStatus.booked,
    createdAt: now,
    technicianId: technician.uid,
    technicianName: technician.name,
    branchId: branch.id,
    branchName: branch.name,
  );

  Widget dashboard({
    List<AppUser> pendingRequests = const [],
    List<AppNotification> approvalNotifications = const [],
    List<AppUser>? technicianRoster,
    String? initialMonitoringTechnicianId,
    List<TechnicianLocation> travelHistory = const [],
    List<OvertimeRecord> overtimeRecords = const [],
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(branchAdmin)),
        branchesProvider.overrideWith((ref) => Stream.value([branch])),
        allBookingsProvider.overrideWith((ref) => Stream.value([booking])),
        techniciansProvider.overrideWith(
          (ref) => Stream.value(technicianRoster ?? [technician]),
        ),
        customersProvider.overrideWith((ref) => Stream.value([customer])),
        allBillsProvider.overrideWith(
          (ref) => Stream.value(<Bill>[]),
        ),
        allReviewsProvider.overrideWith(
          (ref) => Stream.value(<Review>[]),
        ),
        activeTechnicianLocationsProvider.overrideWith(
          (ref) => Stream.value(<TechnicianLocation>[]),
        ),
        attendanceProvider.overrideWith(
          (ref) => Stream.value(<Attendance>[]),
        ),
        pendingTechnicianRequestsProvider.overrideWith(
          (ref) => Stream.value(pendingRequests),
        ),
        branchApprovalNotificationsProvider.overrideWith(
          (ref) => Stream.value(approvalNotifications),
        ),
        technicianTravelHistoryProvider.overrideWith(
          (ref, technicianId) => Stream.value(travelHistory),
        ),
        adminOvertimeProvider.overrideWith(
          (ref) => Stream.value(overtimeRecords),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AdminDashboardScreen(
          initialMonitoringTechnicianId: initialMonitoringTechnicianId,
        ),
      ),
    );
  }

  testWidgets('Branch Admin dashboard is locked to the assigned branch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(find.text('FixNow Branch Admin'), findsWidgets);
    expect(find.text('Branch operations'), findsOneWidget);
    expect(find.text(branch.name), findsWidgets);
    expect(find.text('Branch locked'), findsOneWidget);
    expect(find.text('Add branch'), findsNothing);
    expect(find.text('Edit current branch'), findsNothing);
    expect(find.text('Create Branch Admin'), findsNothing);

    await tester.tap(find.text('Technicians'));
    await tester.pumpAndSettle();
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('Branch Admin dashboard remains responsive on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Overview'), findsWidgets);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Technicians'), findsWidgets);
    expect(find.text('Branch locked'), findsOneWidget);
  });

  testWidgets('Branch Admin revenue dashboard stays locked to its branch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revenue & reports'));
    await tester.pumpAndSettle();

    expect(find.text('Branch revenue dashboard'), findsOneWidget);
    expect(find.text('Yearly revenue'), findsOneWidget);
    expect(find.text('Technician revenue'), findsOneWidget);
    expect(find.text('Service revenue'), findsOneWidget);
    expect(find.text('Revenue reports'), findsOneWidget);
    expect(find.text('Revenue branch'), findsNothing);
    expect(find.text('All branches'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Branch Admin performance stays locked to its branch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    expect(find.text('Branch technician performance'), findsOneWidget);
    expect(find.text('Technician leaderboard'), findsOneWidget);
    expect(find.text('Customer satisfaction'), findsOneWidget);
    expect(find.text('Performance branch'), findsNothing);
    expect(find.text('All branches'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive technician stays visible with reason and reactivation',
      (
    tester,
  ) async {
    final inactiveTechnician = AppUser(
      uid: 'inactive-tech',
      name: 'Meena Kumar',
      email: 'meena@fixnow.test',
      phone: '9999999992',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      createdAt: now,
      isActive: false,
      branchId: branch.id,
      branchName: branch.name,
      inactivatedAt: DateTime(2026, 7, 12, 18, 30),
      inactivatedBy: branchAdmin.uid,
      inactivationReason: 'Technician moved to another branch.',
    );

    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(technicianRoster: [inactiveTechnician]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technicians'));
    await tester.pumpAndSettle();

    expect(find.text('Inactive'), findsOneWidget);
    expect(
      find.text('Inactive: Technician moved to another branch.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Reactivate technician'), findsOneWidget);

    await tester.tap(find.byTooltip('Reactivate technician'));
    await tester.pumpAndSettle();
    expect(find.text('Reactivate technician?'), findsOneWidget);
    expect(
      find.textContaining('able to sign in and receive bookings again'),
      findsOneWidget,
    );
  });

  testWidgets('pending technician displays notification badge and reason form',
      (
    tester,
  ) async {
    final pendingTechnician = AppUser(
      uid: 'pending-tech',
      name: 'Pending Technician',
      email: 'pending@fixnow.test',
      phone: '9999999996',
      role: UserRole.technician,
      accountStatus: AccountStatus.pendingApproval,
      createdAt: now,
      isActive: false,
      branchId: branch.id,
      branchName: branch.name,
    );
    final notification = AppNotification(
      id: 'technician_registration_pending-tech',
      userId: 'branch:${branch.id}',
      title: 'Technician approval requested',
      body: 'Pending Technician requested access.',
      type: 'technicianRegistration',
      createdAt: now,
      isRead: false,
      branchId: branch.id,
      recipientRole: UserRole.branchAdmin.name,
      technicianId: pendingTechnician.uid,
    );

    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(
        pendingRequests: [pendingTechnician],
        approvalNotifications: [notification],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.text('1 new technician approval notification for this branch.'),
      findsOneWidget,
    );
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reason for rejection'), findsOneWidget);
    expect(find.text('Reject request'), findsOneWidget);
  });

  testWidgets('admin can inspect and replay technician travel history', (
    tester,
  ) async {
    final history = [
      TechnicianLocation(
        technicianId: technician.uid,
        latitude: 13.0827,
        longitude: 80.2707,
        updatedAt: DateTime(2026, 7, 13, 9, 20),
        speed: 4,
        accuracy: 5,
        branchId: branch.id,
      ),
      TechnicianLocation(
        technicianId: technician.uid,
        latitude: 13.0877,
        longitude: 80.2757,
        updatedAt: DateTime(2026, 7, 13, 9, 35),
        speed: 8,
        accuracy: 4,
        activeBookingId: booking.id,
        branchId: branch.id,
      ),
    ];
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      dashboard(
        initialMonitoringTechnicianId: technician.uid,
        travelHistory: history,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ravi Kumar travel replay'), findsOneWidget);
    expect(find.text('Replay journey'), findsOneWidget);
    expect(find.text('Travel timeline'), findsOneWidget);
    expect(find.text('Visited locations'), findsWidgets);
    expect(find.text('Tracking window: 9:20 AM - 10:00 PM'), findsOneWidget);
  });

  testWidgets('Branch Admin sees overtime duration and extra work', (
    tester,
  ) async {
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
    await tester.pumpWidget(
      dashboard(
        initialMonitoringTechnicianId: technician.uid,
        overtimeRecords: [overtime],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overtime monitoring'), findsOneWidget);
    expect(find.text('WORKING OVERTIME'), findsOneWidget);
    expect(find.textContaining('1h 12m'), findsOneWidget);
    expect(find.textContaining('1 extra booking'), findsOneWidget);
  });
}
