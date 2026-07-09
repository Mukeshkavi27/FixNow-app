import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums/user_role.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_error_screen.dart';
import '../../features/auth/presentation/approval_pending_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/bookings/presentation/booking_detail_screen.dart';
import '../../features/customer/presentation/book_service_screen.dart';
import '../../features/customer/presentation/customer_dashboard_screen.dart';
import '../../features/customer/presentation/customer_history_screen.dart';
import '../../features/customer/presentation/customer_profile_screen.dart';
import '../../features/technician/presentation/technician_dashboard_screen.dart';
import '../widgets/splash_screen.dart';

final _splashStartedAt = DateTime.now();
const _minimumSplashDuration = Duration(seconds: 3);

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuthLoading = auth.isLoading || user.isLoading;
      final location = state.matchedLocation;
      final splashIsStillWarm =
          DateTime.now().difference(_splashStartedAt) < _minimumSplashDuration;
      if (isAuthLoading) return location == '/splash' ? null : '/splash';
      if (location == '/splash' && splashIsStillWarm) return null;

      final firebaseUser = auth.valueOrNull;
      final appUser = user.valueOrNull;

      if (firebaseUser == null) return location == '/login' ? null : '/login';
      if (user.hasError) {
        return location == '/auth-error' ? null : '/auth-error';
      }
      if (appUser == null) return '/login';
      if (!appUser.isActive) {
        return location == '/approval-pending' ? null : '/approval-pending';
      }
      final home = switch (appUser.role) {
        UserRole.customer => '/customer',
        UserRole.technician => '/technician',
        UserRole.admin => '/admin',
      };
      if (location == '/login' ||
          location == '/splash' ||
          location == '/approval-pending' ||
          location == '/auth-error') {
        return home;
      }

      final isRoleDashboard = location == '/customer' ||
          location == '/technician' ||
          location == '/admin';
      if (isRoleDashboard && location != home) return home;
      if (location.startsWith('/book/') && appUser.role != UserRole.customer) {
        return home;
      }
      if (location.startsWith('/customer/') &&
          appUser.role != UserRole.customer) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(
          path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/approval-pending',
        builder: (context, state) => const ApprovalPendingScreen(),
      ),
      GoRoute(
        path: '/auth-error',
        builder: (context, state) => const AuthErrorScreen(),
      ),
      GoRoute(
          path: '/customer',
          builder: (context, state) => const CustomerDashboardScreen()),
      GoRoute(
        path: '/customer/history',
        builder: (context, state) => const CustomerHistoryScreen(),
      ),
      GoRoute(
        path: '/customer/profile',
        builder: (context, state) => const CustomerProfileScreen(),
      ),
      GoRoute(
        path: '/book/:appliance',
        builder: (context, state) => BookServiceScreen(
          appliance: Uri.decodeComponent(state.pathParameters['appliance']!),
        ),
      ),
      GoRoute(
        path: '/booking/:id/confirmed',
        builder: (context, state) => BookingDetailScreen(
          bookingId: state.pathParameters['id']!,
          showConfirmation: true,
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
      appBar: AppBar(title: const Text('FixNow Appliance Repair')),
      body: Center(child: Text(state.error.toString())),
    ),
  );
});
