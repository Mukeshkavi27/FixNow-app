import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums/user_role.dart';
import '../../core/auth/app_permission.dart';
import '../../core/auth/route_access.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_error_screen.dart';
import '../../features/auth/presentation/access_denied_screen.dart';
import '../../features/auth/presentation/approval_pending_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/bookings/presentation/booking_detail_screen.dart';
import '../../features/customer/presentation/book_service_screen.dart';
import '../../features/customer/presentation/customer_dashboard_screen.dart';
import '../../features/customer/presentation/customer_history_screen.dart';
import '../../features/customer/presentation/customer_profile_screen.dart';
import '../../features/customer/presentation/customer_service_search_screen.dart';
import '../../features/technician/presentation/technician_dashboard_screen.dart';
import '../../features/super_admin/presentation/super_admin_dashboard_screen.dart';
import '../widgets/splash_screen.dart';

final _splashStartedAt = DateTime.now();
const _minimumSplashDuration = Duration(milliseconds: 350);

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

String _homeForRole(UserRole role) => switch (role) {
      UserRole.customer => '/customer',
      UserRole.technician => '/technician',
      UserRole.branchAdmin => '/admin',
      UserRole.superAdmin => '/super-admin',
    };

final appRouterProvider = Provider<GoRouter>((ref) {
  // Keep imperative pushes visible in the browser URL so customer sub-pages
  // support refresh, deep links, and normal browser back/forward navigation.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final refreshNotifier = _RouterRefreshNotifier();
  ref
    ..onDispose(refreshNotifier.dispose)
    ..listen(authStateProvider, (_, __) => refreshNotifier.refresh())
    ..listen(currentUserProvider, (_, __) => refreshNotifier.refresh());

  return GoRouter(
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final user = ref.read(currentUserProvider);
      final isAuthLoading = auth.isLoading || user.isLoading;
      final location = state.matchedLocation;
      final splashIsStillWarm =
          DateTime.now().difference(_splashStartedAt) < _minimumSplashDuration;
      if (isAuthLoading) {
        if (location == '/splash') return null;
        final intended = Uri.encodeComponent(state.uri.toString());
        return '/splash?redirect=$intended';
      }
      if (location == '/splash' && splashIsStillWarm) return null;

      final firebaseUser = auth.valueOrNull;
      final appUser = user.valueOrNull;

      if (user.hasError) {
        return location == '/auth-error' ? null : '/auth-error';
      }
      if (firebaseUser == null) return location == '/login' ? null : '/login';
      if (appUser == null) {
        return location == '/auth-error' ? null : '/auth-error';
      }
      if (appUser.accessDenialReason != null) {
        return location == '/approval-pending' ? null : '/approval-pending';
      }
      final home = _homeForRole(appUser.role);
      if (location == '/') return home;
      if (location == '/splash') {
        final intended = state.uri.queryParameters['redirect'];
        if (intended == null || intended == '/' || intended == '/splash') {
          return home;
        }
        final intendedPath = Uri.tryParse(intended)?.path ?? intended;
        final intendedPermission = requiredPermissionForLocation(intendedPath);
        return intendedPermission == null ||
                RolePermissions.allows(appUser.role, intendedPermission)
            ? intended
            : '/access-denied';
      }
      if (location == '/login' ||
          location == '/approval-pending' ||
          location == '/auth-error') {
        return home;
      }

      if (location == '/access-denied') return null;
      final permission = requiredPermissionForLocation(location);
      if (permission != null &&
          !RolePermissions.allows(appUser.role, permission)) {
        return '/access-denied';
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
        path: '/access-denied',
        builder: (context, state) => const AccessDeniedScreen(),
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
        path: '/customer/search',
        builder: (context, state) => const CustomerServiceSearchScreen(),
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
      GoRoute(
        path: '/super-admin',
        builder: (context, state) => const SuperAdminDashboardScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('FixNow Appliance Repair')),
      body: const Center(
        child:
            Text('This page could not be opened. Please return and try again.'),
      ),
    ),
  );
});
