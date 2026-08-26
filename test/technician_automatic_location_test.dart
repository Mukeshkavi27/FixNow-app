import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/core/services/location_tracking_service.dart';
import 'package:fixnow/features/auth/data/auth_repository.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/review.dart';
import 'package:fixnow/features/technician/domain/attendance.dart';
import 'package:fixnow/features/technician/domain/overtime_record.dart';
import 'package:fixnow/features/technician/presentation/technician_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('technician location write throttling', () {
    final start = DateTime(2026, 8, 20, 9);

    test('publishes current location at most once per minute', () {
      expect(
        shouldPublishTechnicianLocation(
          now: start.add(const Duration(seconds: 59)),
          lastPublishedAt: start,
        ),
        isFalse,
      );
      expect(
        shouldPublishTechnicianLocation(
          now: start.add(const Duration(minutes: 1)),
          lastPublishedAt: start,
        ),
        isTrue,
      );
    });

    test('force publish bypasses the current location interval', () {
      expect(
        shouldPublishTechnicianLocation(
          now: start.add(const Duration(seconds: 5)),
          lastPublishedAt: start,
          force: true,
        ),
        isTrue,
      );
    });

    test('records route history every minute while moving', () {
      expect(
        shouldRecordTechnicianLocationHistory(
          now: start.add(const Duration(seconds: 59)),
          lastRecordedAt: start,
        ),
        isFalse,
      );
      expect(
        shouldRecordTechnicianLocationHistory(
          now: start.add(const Duration(minutes: 1)),
          lastRecordedAt: start,
        ),
        isTrue,
      );
    });

    test('records route history every minute while stationary', () {
      expect(
        shouldRecordTechnicianLocationHistory(
          now: start.add(const Duration(seconds: 59)),
          lastRecordedAt: start,
        ),
        isFalse,
      );
      expect(
        shouldRecordTechnicianLocationHistory(
          now: start.add(const Duration(minutes: 1)),
          lastRecordedAt: start,
        ),
        isTrue,
      );
    });
  });

  group('technician location integrity', () {
    test('accepts a precise physical-device sample', () {
      expect(
        isAcceptableTechnicianPosition(
          latitude: 11.0168,
          longitude: 76.9558,
          accuracy: 12,
          isMocked: false,
        ),
        isTrue,
      );
    });

    test('rejects mocked, invalid, and low-confidence samples', () {
      expect(
        isAcceptableTechnicianPosition(
          latitude: 11.0168,
          longitude: 76.9558,
          accuracy: 12,
          isMocked: true,
        ),
        isFalse,
      );
      expect(
        isAcceptableTechnicianPosition(
          latitude: 91,
          longitude: 76.9558,
          accuracy: 12,
          isMocked: false,
        ),
        isFalse,
      );
      expect(
        isAcceptableTechnicianPosition(
          latitude: 11.0168,
          longitude: 76.9558,
          accuracy: 251,
          isMocked: false,
        ),
        isFalse,
      );
    });
  });

  test('attendance location fallback is restricted to local hosts', () {
    expect(isLocalAttendanceHost('localhost'), isTrue);
    expect(isLocalAttendanceHost('127.0.0.1'), isTrue);
    expect(isLocalAttendanceHost('::1'), isTrue);
    expect(isLocalAttendanceHost('app.fixnow.in'), isFalse);
  });

  testWidgets('location waits for attendance, then starts for active booking', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 20, 10);
    final user = AppUser(
      uid: 'tech-1',
      name: 'Technician',
      email: 'tech@fixnow.test',
      phone: '9999999999',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      createdAt: now,
      isActive: true,
      branchId: 'branch-1',
      branchName: 'FixNow Coimbatore',
    );
    final booking = Booking(
      id: 'booking-1',
      customerId: 'customer-1',
      customerName: 'Customer',
      phone: '9999999998',
      address: 'Coimbatore',
      applianceType: 'Air Conditioner',
      problemDescription: 'Not cooling',
      preferredDate: now,
      preferredTime: '10:00 AM',
      status: BookingStatus.technicianAssigned,
      createdAt: now,
      technicianId: user.uid,
      technicianName: user.name,
      branchId: user.branchId,
      branchName: user.branchName,
    );
    final tracker = _FakeLocationTrackingController();

    Widget dashboard(List<Attendance> attendance) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(user)),
            technicianBookingsProvider.overrideWith(
              (ref) => Stream.value([booking]),
            ),
            technicianBillsProvider.overrideWith(
              (ref) => Stream.value(<Bill>[]),
            ),
            currentTechnicianReviewsProvider.overrideWith(
              (ref) => Stream.value(<Review>[]),
            ),
            technicianAttendanceProvider.overrideWith(
              (ref) => Stream.value(attendance),
            ),
            technicianOvertimeProvider.overrideWith(
              (ref) => Stream.value(<OvertimeRecord>[]),
            ),
            technicianLiveLocationProvider.overrideWith(
              (ref, technicianId) => Stream.value(null),
            ),
            technicianBookingBillProvider.overrideWith(
              (ref, bookingId) => Stream.value(null),
            ),
            locationTrackingServiceProvider.overrideWithValue(tracker),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const TechnicianDashboardScreen(),
          ),
        );

    await tester.pumpWidget(dashboard(const []));
    await tester.pumpAndSettle();

    expect(tracker.startCount, 0);
    expect(find.text('OFF DUTY'), findsOneWidget);
    expect(
      find.byTooltip('Off duty - location starts after attendance'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      dashboard([
        Attendance(
          id: 'attendance-1',
          technicianId: user.uid,
          selfieUrl: 'selfie',
          latitude: 11.0,
          longitude: 77.0,
          timestamp: DateTime.now(),
          status: 'present',
          faceMatchPassed: true,
          geofencePassed: true,
          branchId: user.branchId,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow workday location tracking?'), findsOneWidget);
    expect(
      find.textContaining('including when the app is in the background'),
      findsOneWidget,
    );
    expect(tracker.startCount, 0);
    await tester.tap(find.text('Agree & continue'));
    await tester.pumpAndSettle();

    expect(tracker.startCount, 1);
    expect(tracker.technicianId, user.uid);
    expect(tracker.branchId, user.branchId);
    expect(tracker.bookingId, booking.id);
    expect(find.text('LIVE'), findsOneWidget);
    expect(
      find.byTooltip('Location is automatically shared'),
      findsOneWidget,
    );
    expect(find.byTooltip('My profile'), findsOneWidget);
    await tester.tap(find.byTooltip('My profile'));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text(user.email), findsOneWidget);
    expect(find.text('Current branch'), findsOneWidget);
    expect(find.text('Performance summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeLocationTrackingController implements LocationTrackingController {
  int startCount = 0;
  String? technicianId;
  String? branchId;
  String? bookingId;

  @override
  bool get isTracking => startCount > 0;

  @override
  String? get activeBookingId => bookingId;

  @override
  Future<void> startShift({
    required String technicianId,
    required String branchId,
    String? bookingId,
  }) async {
    startCount++;
    this.technicianId = technicianId;
    this.branchId = branchId;
    this.bookingId = bookingId;
  }

  @override
  Future<void> start({
    required String technicianId,
    required String bookingId,
    String? branchId,
  }) async {}

  @override
  Future<void> startWorkingDay({
    required String technicianId,
    String? branchId,
    String? bookingId,
  }) async {}

  @override
  Future<void> finishBooking() async {}

  @override
  Future<bool> recoverNow() async => true;

  @override
  Future<void> stop() async {}
}
