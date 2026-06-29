import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/data/auth_repository.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/customer/presentation/customer_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final customer = AppUser(
    uid: 'customer-1',
    name: 'Responsive Customer',
    email: 'customer@example.com',
    phone: '9999999999',
    role: UserRole.customer,
    createdAt: DateTime(2026, 6, 12),
    isActive: true,
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(customer)),
          customerBookingsProvider.overrideWith(
            (ref) => Stream.value(<Booking>[]),
          ),
        ],
        child: const MaterialApp(home: CustomerDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('customer dashboard fits a narrow mobile viewport', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(
      find.text('Home appliance repair,\nright when you need it'),
      findsOneWidget,
    );
  });

  testWidgets('customer dashboard uses a bounded desktop layout', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(1280, 900));

    expect(tester.takeException(), isNull);
    final dashboardSize = tester.getSize(
      find.byType(CustomScrollView),
    );
    expect(dashboardSize.width, lessThanOrEqualTo(1180));
  });
}
