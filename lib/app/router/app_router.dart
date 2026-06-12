import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums/user_role.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/bookings/presentation/booking_detail_screen.dart';
import '../../features/customer/presentation/book_service_screen.dart';
import '../../features/customer/presentation/customer_dashboard_screen.dart';
import '../../features/technician/presentation/technician_dashboard_screen.dart';
import '../widgets/splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuthLoading = auth.isLoading || user.isLoading;
      if (isAuthLoading) return '/splash';

      final firebaseUser = auth.valueOrNull;
      final appUser = user.valueOrNull;
      final location = state.matchedLocation;

      if (firebaseUser == null) return location == '/login' ? null : '/login';
      if (appUser == null || !appUser.isActive) return '/login';
      final home = switch (appUser.role) {
        UserRole.customer => '/customer',
        UserRole.technician => '/technician',
        UserRole.admin => '/admin',
      };
      if (location == '/login' || location == '/splash') return home;

      final isRoleDashboard = location == '/customer' ||
          location == '/technician' ||
          location == '/admin';
      if (isRoleDashboard && location != home) return home;
      if (location.startsWith('/book/') && appUser.role != UserRole.customer) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(
          path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/customer',
          builder: (context, state) => const CustomerDashboardScreen()),
      GoRoute(
        path: '/book/:appliance',
        builder: (context, state) => BookServiceScreen(
          appliance: Uri.decodeComponent(state.pathParameters['appliance']!),
        ),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (context, state) =>
            BookingDetailScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
          path: '/technician',
          builder: (context, state) => const TechnicianDashboardScreen()),
      GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('FixNow')),
      body: Center(child: Text(state.error.toString())),
    ),
  );
});
