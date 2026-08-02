import 'package:fixnow/app/theme/app_theme.dart';
import 'package:fixnow/app/widgets/fixnow_admin_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const destinations = [
    FixNowAdminDestination(
      id: 'overview',
      label: 'Overview',
      icon: Icons.dashboard_outlined,
    ),
    FixNowAdminDestination(
      id: 'bookings',
      label: 'Bookings',
      icon: Icons.assignment_outlined,
    ),
  ];

  Widget shell({bool loading = false}) => MaterialApp(
        theme: AppTheme.light,
        home: FixNowAdminShell(
          destinations: destinations,
          selectedId: 'overview',
          onDestinationSelected: (_) {},
          userName: 'Admin User',
          roleLabel: 'Branch Admin',
          consoleLabel: 'FixNow Admin Console',
          contextLabel: 'FixNow Chennai',
          isLoading: loading,
          body: loading
              ? const FixNowAdminSkeleton(label: 'Loading admin dashboard')
              : const Center(child: Text('Dashboard content')),
        ),
      );

  testWidgets('shared admin shell renders desktop navigation and hover states',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.text('FixNow'), findsOneWidget);
    expect(find.text('FixNow Admin Console'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Admin User'), findsWidgets);
    expect(find.text('Dashboard content'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Bookings')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared admin shell uses responsive drawer on mobile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.text('Dashboard content'), findsOneWidget);
    expect(find.byTooltip('Change dashboard section'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('FixNow Admin Console'), findsOneWidget);
    expect(find.text('Bookings'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin skeleton animates without layout errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(shell(loading: true));
    await tester.pump(const Duration(milliseconds: 450));

    expect(
      find.bySemanticsLabel('Loading admin dashboard'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
