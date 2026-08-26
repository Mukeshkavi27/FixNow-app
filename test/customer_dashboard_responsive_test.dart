import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/branches/branch_repository.dart';
import 'package:fixnow/core/constants/app_constants.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/features/auth/data/auth_repository.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/customer/presentation/customer_dashboard_screen.dart';
import 'package:fixnow/features/customer/presentation/customer_history_screen.dart';
import 'package:fixnow/features/customer/presentation/customer_service_search_screen.dart';
import 'package:fixnow/features/services/data/service_catalog_repository.dart';
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
          branchesProvider.overrideWith(
            (ref) => Stream.value(const <BranchInfo>[]),
          ),
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
    final hero = tester.getRect(
      find.byKey(const Key('customer-welcome-hero')),
    );
    final search = tester.getRect(
      find.byKey(const Key('customer-service-search')),
    );
    final support = tester.getRect(
      find.byKey(const Key('customer-mobile-support')),
    );
    expect(search.top, greaterThan(hero.bottom));
    expect(support.top, greaterThan(search.bottom));
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

  testWidgets('service search filters as the customer types', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceCatalogProvider.overrideWith(
            (ref) => Stream.value(const [
              ApplianceCategory('Air Conditioner', 'Starting at Rs. 499', ''),
              ApplianceCategory('Washing Machine', 'Starting at Rs. 399', ''),
            ]),
          ),
        ],
        child: const MaterialApp(home: CustomerServiceSearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('service-search-field')),
      'washing',
    );
    await tester.pump();

    expect(find.text('Washing Machine'), findsOneWidget);
    expect(find.text('Air Conditioner'), findsNothing);
  });

  testWidgets('AC search resolves to Air Conditioner, not accidental letters',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceCatalogProvider.overrideWith(
            (ref) => Stream.value(const [
              ApplianceCategory('Air Conditioner', 'Starting at Rs. 499', ''),
              ApplianceCategory('Washing Machine', 'Starting at Rs. 399', ''),
            ]),
          ),
        ],
        child: const MaterialApp(home: CustomerServiceSearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('service-search-field')),
      'AC',
    );
    await tester.pump();

    expect(find.text('Air Conditioner'), findsOneWidget);
    expect(find.text('Washing Machine'), findsNothing);
  });

  test('completed customer work is history, not active', () {
    expect(isCustomerHistoryStatus(BookingStatus.serviceCompleted), isTrue);
    expect(isCustomerHistoryStatus(BookingStatus.closed), isTrue);
    expect(isCustomerActiveStatus(BookingStatus.estimateSent), isTrue);
    expect(isCustomerActiveStatus(BookingStatus.billGenerated), isTrue);
  });
}
