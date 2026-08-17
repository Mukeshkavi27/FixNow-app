import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/app_config_repository.dart';
import '../../../core/enums/booking_status.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../core/maps/google_static_map.dart';
import '../../../core/maps/route_recalculation.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/face_match_service.dart';
import '../../../core/services/location_tracking_service.dart';
import '../../../core/services/push_token_service.dart';
import '../../../core/services/reverse_geocoding_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../estimates/data/estimate_repository.dart';
import '../../estimates/domain/estimate.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/data/cloudinary_repository.dart';
import '../../shared/data/review_repository.dart';
import '../../shared/data/storage_repository.dart';
import '../../shared/data/technician_incentive_repository.dart';
import '../../shared/domain/bill.dart';
import '../../shared/domain/review.dart';
import '../../shared/domain/technician_incentive.dart';
import '../../shared/domain/technician_compensation.dart';
import '../data/technician_repository.dart';
import '../domain/attendance.dart';
import '../domain/overtime_record.dart';
import '../domain/technician_location.dart';
import 'overtime_summary_panel.dart';

final technicianBookingsProvider =
    StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchTechnicianBookings(user.uid);
});

final technicianBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Bill>[]);
  return ref.watch(billRepositoryProvider).watchTechnicianBills(user.uid);
});

final currentTechnicianReviewsProvider =
    StreamProvider.autoDispose<List<Review>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Review>[]);
  return ref.watch(reviewRepositoryProvider).watchTechnicianReviews(user.uid);
});

final technicianAttendanceProvider =
    StreamProvider.autoDispose<List<Attendance>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Attendance>[]);
  return ref
      .watch(technicianRepositoryProvider)
      .watchTechnicianAttendance(user.uid);
});

final technicianOvertimeProvider =
    StreamProvider.autoDispose<List<OvertimeRecord>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<OvertimeRecord>[]);
  return ref
      .watch(technicianRepositoryProvider)
      .watchTechnicianOvertime(user.uid);
});

final technicianEstimateProvider =
    StreamProvider.autoDispose.family<Estimate?, String>((ref, bookingId) {
  return ref.watch(estimateRepositoryProvider).watchForBooking(bookingId);
});

final technicianBookingBillProvider =
    StreamProvider.autoDispose.family<Bill?, String>((ref, bookingId) {
  return ref.watch(billRepositoryProvider).watchForBooking(bookingId);
});

final technicianLiveLocationProvider = StreamProvider.autoDispose
    .family<TechnicianLocation?, String>((ref, technicianId) {
  return ref.watch(technicianRepositoryProvider).watchLocation(technicianId);
});

final technicianAddressPinProvider =
    FutureProvider.autoDispose.family<AddressGeocodingResult?, String>(
  (ref, address) {
    return ref.watch(addressGeocodingServiceProvider).search(address);
  },
);

final _technicianTabProvider = StateProvider.autoDispose<int>((ref) => 0);
final _earningsRangeProvider =
    StateProvider.autoDispose<_EarningsRange>((ref) => _EarningsRange.week);

bool isLocalAttendanceHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

enum _EarningsRange {
  week('Week'),
  month('Month');

  const _EarningsRange(this.label);
  final String label;
}

enum _AutomaticLocationState {
  waitingForAttendance,
  starting,
  sharing,
  permissionRequired,
  profileRequired,
}

class TechnicianDashboardScreen extends ConsumerStatefulWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  ConsumerState<TechnicianDashboardScreen> createState() =>
      _TechnicianDashboardScreenState();
}

class _TechnicianDashboardScreenState
    extends ConsumerState<TechnicianDashboardScreen> {
  _AutomaticLocationState _locationState =
      _AutomaticLocationState.waitingForAttendance;
  String? _requestedTrackingKey;
  String? _pushRegistrationUserId;

  void _schedulePushRegistration(String userId) {
    if (_pushRegistrationUserId == userId) return;
    _pushRegistrationUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await PushTokenService.instance.registerTechnician(
          userId: userId,
          firestore: ref.read(firebaseRefsProvider).firestore,
        );
      } catch (_) {
        // Notification permission or token failures must not block jobs,
        // attendance, or location sharing. The next app session retries.
      }
    });
  }

  void _scheduleAutomaticLocation({
    required String technicianId,
    required String? branchId,
    required String? bookingId,
  }) {
    final key = '$technicianId|${branchId ?? ''}|${bookingId ?? ''}';
    if (_requestedTrackingKey == key) return;
    _requestedTrackingKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startAutomaticLocation(
        technicianId: technicianId,
        branchId: branchId,
        bookingId: bookingId,
      );
    });
  }

  Future<void> _startAutomaticLocation({
    required String technicianId,
    required String? branchId,
    required String? bookingId,
    bool force = false,
  }) async {
    final normalizedBranchId = branchId?.trim() ?? '';
    if (normalizedBranchId.isEmpty) {
      if (mounted) {
        setState(() {
          _locationState = _AutomaticLocationState.profileRequired;
        });
      }
      return;
    }
    final service = ref.read(locationTrackingServiceProvider);
    if (!force && service.isTracking) {
      if (bookingId != null && service.activeBookingId != bookingId) {
        await service.start(
          technicianId: technicianId,
          bookingId: bookingId,
          branchId: normalizedBranchId,
        );
      }
      if (mounted) {
        setState(() => _locationState = _AutomaticLocationState.sharing);
      }
      return;
    }
    if (mounted) {
      setState(() => _locationState = _AutomaticLocationState.starting);
    }
    try {
      await service.startShift(
        technicianId: technicianId,
        branchId: normalizedBranchId,
        bookingId: bookingId,
      );
      if (mounted) {
        setState(() => _locationState = _AutomaticLocationState.sharing);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationState = _AutomaticLocationState.permissionRequired;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Automatic location could not start. Enable device location permission and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _closeTodaysWork(String technicianId) async {
    final firstConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close today\'s work?'),
        content: const Text(
          'Your Branch Admin and Super Admin will no longer receive your live location after you close today\'s work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep tracking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstConfirmation != true || !mounted) return;
    final finalConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Final confirmation'),
        content: const Text(
          'This ends today\'s location recording. You can only restart it by marking attendance on a new workday.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close today\'s work'),
          ),
        ],
      ),
    );
    if (finalConfirmation != true) return;
    await ref.read(locationTrackingServiceProvider).stop();
    if (!mounted) return;
    setState(
        () => _locationState = _AutomaticLocationState.waitingForAttendance);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Today\'s work closed. Location tracking stopped.')),
    );
  }

  String get _locationTooltip => switch (_locationState) {
        _AutomaticLocationState.waitingForAttendance =>
          'Off duty - location starts after attendance',
        _AutomaticLocationState.starting => 'Starting automatic location',
        _AutomaticLocationState.sharing => 'Location is automatically shared',
        _AutomaticLocationState.permissionRequired =>
          'Enable location permission and retry',
        _AutomaticLocationState.profileRequired =>
          'Branch assignment is required for location sharing',
      };

  Widget get _locationIcon => switch (_locationState) {
        _AutomaticLocationState.waitingForAttendance =>
          const Icon(Icons.work_off_outlined),
        _AutomaticLocationState.starting => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _AutomaticLocationState.sharing => const Icon(Icons.location_on),
        _AutomaticLocationState.permissionRequired =>
          const Icon(Icons.location_disabled),
        _AutomaticLocationState.profileRequired =>
          const Icon(Icons.wrong_location_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(_technicianTabProvider);
    final visibleTab = tab > 3 ? 3 : tab;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final bookings = ref.watch(technicianBookingsProvider).valueOrNull;
    final attendance = ref.watch(technicianAttendanceProvider).valueOrNull;
    final activeBooking = user == null || bookings == null
        ? null
        : findTechnicianActiveBooking(bookings, user.uid);
    final liveLocation = user == null
        ? null
        : ref.watch(technicianLiveLocationProvider(user.uid)).valueOrNull;
    final todayAttendance = user == null || attendance == null
        ? null
        : attendance.cast<Attendance?>().firstWhere(
              (record) =>
                  record?.technicianId == user.uid &&
                  _sameCalendarDay(record!.timestamp, DateTime.now()),
              orElse: () => null,
            );
    final workingToday = todayAttendance?.status == 'present' ||
        todayAttendance?.status == 'late';
    final selfDeclaredLeave =
        todayAttendance?.locationSource == 'leaveConfirmation';
    // A legacy automatic-absence record must not prevent the technician from
    // correcting it by completing late selfie + location attendance.
    final checkedInToday = todayAttendance != null &&
        (todayAttendance.status != 'absent' || selfDeclaredLeave);
    final workClosedToday = liveLocation?.shiftClosedAt != null &&
        _sameCalendarDay(liveLocation!.shiftClosedAt!, DateTime.now());
    if (user != null) {
      _schedulePushRegistration(user.uid);
    }
    if (user != null && bookings != null && workingToday && !workClosedToday) {
      _scheduleAutomaticLocation(
        technicianId: user.uid,
        branchId: user.branchId,
        bookingId: activeBooking?.id,
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Hello, ${(user?.name ?? 'Technician').trim().split(' ').first}'),
            const Text(
              'FixNow Technician App',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          _LocationStatusBadge(
            label: switch (_locationState) {
              _AutomaticLocationState.waitingForAttendance => 'OFF DUTY',
              _AutomaticLocationState.starting => 'STARTING',
              _AutomaticLocationState.sharing => 'LIVE',
              _AutomaticLocationState.permissionRequired => 'LOCATION OFF',
              _AutomaticLocationState.profileRequired => 'NO BRANCH',
            },
            tooltip: _locationTooltip,
            icon: _locationIcon,
            color: switch (_locationState) {
              _AutomaticLocationState.waitingForAttendance =>
                AppTheme.textSecondary,
              _AutomaticLocationState.starting => const Color(0xFFF38A1F),
              _AutomaticLocationState.sharing => const Color(0xFF138A52),
              _AutomaticLocationState.permissionRequired ||
              _AutomaticLocationState.profileRequired =>
                const Color(0xFFD95C2A),
            },
            onRetry:
                _locationState == _AutomaticLocationState.permissionRequired &&
                        user != null &&
                        bookings != null &&
                        checkedInToday
                    ? () => _startAutomaticLocation(
                          technicianId: user.uid,
                          branchId: user.branchId,
                          bookingId: activeBooking?.id,
                          force: true,
                        )
                    : null,
          ),
          if (checkedInToday)
            IconButton(
              tooltip: 'View attendance',
              onPressed: _showAttendanceHistory,
              icon: const Icon(Icons.fact_check_outlined),
            ),
          if (workingToday && !workClosedToday)
            IconButton(
              tooltip: 'Close today\'s work',
              onPressed: () => _closeTodaysWork(user!.uid),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          IconButton(
            tooltip: 'My profile',
            onPressed: user == null ? null : () => _showProfile(user),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              try {
                await ref
                    .read(locationTrackingServiceProvider)
                    .stop()
                    .timeout(const Duration(seconds: 8));
              } catch (_) {
                // Sign-out must stay available even if GPS shutdown or the
                // location write takes too long on a device.
              }
              await ref.read(authRepositoryProvider).signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: user == null || attendance == null
            ? const Center(child: CircularProgressIndicator())
            : checkedInToday
                ? Column(
                    children: [
                      if (todayAttendance.status == 'absent')
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: Colors.red.shade50,
                          child: Text(
                            selfDeclaredLeave
                                ? '✕ On Leave Today'
                                : '✕ Attendance not marked by 9:45 AM',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      Expanded(
                        child: IndexedStack(
                          index: visibleTab,
                          children: const [
                            _JobsView(),
                            _JobHistoryView(),
                            _EarningsView(),
                            _TechnicianReviewsView(),
                          ],
                        ),
                      ),
                    ],
                  )
                : const _AttendanceGateView(),
      ),
      bottomNavigationBar: checkedInToday
          ? NavigationBar(
              selectedIndex: visibleTab,
              onDestinationSelected: (index) =>
                  ref.read(_technicianTabProvider.notifier).state = index,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.work_outline),
                    selectedIcon: Icon(Icons.work),
                    label: 'Jobs'),
                NavigationDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history),
                    label: 'History'),
                NavigationDestination(
                    icon: Icon(Icons.payments_outlined),
                    selectedIcon: Icon(Icons.payments),
                    label: 'Earnings'),
                NavigationDestination(
                    icon: Icon(Icons.star_outline),
                    selectedIcon: Icon(Icons.star),
                    label: 'Reviews'),
              ],
            )
          : null,
    );
  }

  void _showAttendanceHistory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, _) {
            final attendanceAsync = ref.watch(technicianAttendanceProvider);
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'My attendance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TechnicianAttendanceHistory(attendanceAsync: attendanceAsync),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showProfile(AppUser user) {
    showDialog<void>(
      context: context,
      builder: (context) => _TechnicianProfileDialog(user: user),
    );
  }
}

class _TechnicianProfileDialog extends ConsumerWidget {
  const _TechnicianProfileDialog({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings =
        ref.watch(technicianBookingsProvider).valueOrNull ?? const <Booking>[];
    final bills =
        ref.watch(technicianBillsProvider).valueOrNull ?? const <Bill>[];
    final attendance = ref.watch(technicianAttendanceProvider).valueOrNull ??
        const <Attendance>[];
    final reviews = ref.watch(currentTechnicianReviewsProvider).valueOrNull ??
        const <Review>[];
    final liveLocation =
        ref.watch(technicianLiveLocationProvider(user.uid)).valueOrNull;
    final paidCollections = bills
        .where((bill) => bill.isPaid)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final averageRating = reviews.isEmpty
        ? 0.0
        : reviews.fold<int>(0, (sum, review) => sum + review.rating) /
            reviews.length;
    final presentDays = attendance
        .where((item) => item.status == 'present' || item.status == 'late')
        .length;
    final lateDays = attendance.where((item) => item.status == 'late').length;
    final leaveDays = attendance
        .where((item) => item.locationSource == 'leaveConfirmation')
        .length;
    final completedJobs =
        bookings.where((item) => item.status == BookingStatus.closed).length;
    final activeJobs =
        bookings.where((item) => isTechnicianBusyStatus(item.status)).length;
    final initial = user.name.trim().isEmpty
        ? 'T'
        : user.name.trim().substring(0, 1).toUpperCase();

    return AlertDialog(
      title: const Text('My profile'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TechnicianProfileAvatar(
                    photo: user.profilePhoto,
                    initial: initial,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.trim().isEmpty ? 'Technician' : user.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${user.technicianCategory.label} technician',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        _ProfileStatusPill(
                          label: user.isActive ? 'Active' : 'Inactive',
                          active: user.isActive,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _ProfileSectionTitle('Personal details'),
              _ProfileDetailRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: user.email.isEmpty ? 'Not provided' : user.email,
              ),
              _ProfileDetailRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: user.phone.isEmpty ? 'Not provided' : user.phone,
              ),
              _ProfileDetailRow(
                icon: Icons.verified_user_outlined,
                label: 'Account status',
                value: user.accountStatus.label,
              ),
              _ProfileDetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Joined',
                value: DateFormat('dd MMM yyyy')
                    .format(user.approvedAt ?? user.createdAt),
              ),
              const SizedBox(height: 14),
              const _ProfileSectionTitle('Work details'),
              _ProfileDetailRow(
                icon: Icons.store_outlined,
                label: 'Current branch',
                value: user.branchName ?? 'Not assigned',
              ),
              _ProfileDetailRow(
                icon: Icons.account_balance_outlined,
                label: 'Native revenue branch',
                value:
                    user.nativeBranchName ?? user.branchName ?? 'Not assigned',
              ),
              _ProfileDetailRow(
                icon: Icons.workspace_premium_outlined,
                label: 'Category',
                value: user.technicianCategory.label,
              ),
              _ProfileDetailRow(
                icon: Icons.payments_outlined,
                label: 'Monthly salary',
                value: user.monthlySalary > 0
                    ? 'Rs. ${user.monthlySalary.toStringAsFixed(0)}'
                    : 'Not configured',
              ),
              _ProfileDetailRow(
                icon: Icons.location_on_outlined,
                label: 'Live location',
                value: liveLocation == null
                    ? 'Not currently available'
                    : 'Updated ${DateFormat('dd MMM yyyy, hh:mm a').format(liveLocation.updatedAt)}',
              ),
              _ProfileDetailRow(
                icon: Icons.face_outlined,
                label: 'Face ID',
                value: user.faceReferencePhoto?.trim().isNotEmpty == true
                    ? 'Registered'
                    : 'Not registered',
              ),
              if (user.transferredAt != null)
                _ProfileDetailRow(
                  icon: Icons.swap_horiz,
                  label: 'Last branch transfer',
                  value: DateFormat('dd MMM yyyy, hh:mm a')
                      .format(user.transferredAt!),
                ),
              const SizedBox(height: 14),
              const _ProfileSectionTitle('Performance summary'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ProfileMetric(label: 'Active jobs', value: '$activeJobs'),
                  _ProfileMetric(
                      label: 'Completed jobs', value: '$completedJobs'),
                  _ProfileMetric(
                    label: 'Confirmed collections',
                    value: 'Rs. ${paidCollections.toStringAsFixed(0)}',
                  ),
                  _ProfileMetric(
                      label: 'Attendance days', value: '$presentDays'),
                  _ProfileMetric(label: 'Late days', value: '$lateDays'),
                  _ProfileMetric(label: 'Leave days', value: '$leaveDays'),
                  _ProfileMetric(
                    label: 'Rating',
                    value: reviews.isEmpty
                        ? 'No reviews'
                        : '${averageRating.toStringAsFixed(1)} / 5 (${reviews.length})',
                  ),
                ],
              ),
              if (user.lastServiceAddress?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 14),
                const _ProfileSectionTitle('Last service location'),
                Text(user.lastServiceAddress!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TechnicianProfileAvatar extends StatelessWidget {
  const _TechnicianProfileAvatar({required this.photo, required this.initial});

  final String? photo;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final value = photo?.trim() ?? '';
    Widget child = Text(
      initial,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
    );
    if (value.startsWith('data:image') && value.contains(',')) {
      try {
        child = ClipOval(
          child: Image.memory(
            base64Decode(value.substring(value.indexOf(',') + 1)),
            width: 68,
            height: 68,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    } else if (value.startsWith('http://') || value.startsWith('https://')) {
      child = ClipOval(
        child: Image.network(
          value,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(child: Text(initial)),
        ),
      );
    }
    return CircleAvatar(
      radius: 34,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
      foregroundColor: AppTheme.primary,
      child: child,
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      );
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 9),
            SizedBox(
              width: 145,
              child: Text(
                label,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
}

class _ProfileStatusPill extends StatelessWidget {
  const _ProfileStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF138A52) : const Color(0xFFD95C2A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _AttendanceGateView extends StatelessWidget {
  const _AttendanceGateView();

  @override
  Widget build(BuildContext context) {
    return const _AttendanceView();
  }
}

bool _sameCalendarDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _attendanceStorageDayKey(DateTime day) {
  return DateFormat('yyyy-MM-dd').format(day);
}

class _LocationStatusBadge extends StatelessWidget {
  const _LocationStatusBadge({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    this.onRetry,
  });

  final String label;
  final String tooltip;
  final Widget icon;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: color, size: 16),
            child: SizedBox(width: 16, height: 16, child: icon),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
    return Tooltip(
      message: tooltip,
      child: onRetry == null
          ? Semantics(label: tooltip, child: badge)
          : InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRetry,
              child: badge,
            ),
    );
  }
}

class _JobsView extends ConsumerWidget {
  const _JobsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(technicianBookingsProvider);
    final bills = ref.watch(technicianBillsProvider).valueOrNull ?? const [];
    final overtime =
        ref.watch(technicianOvertimeProvider).valueOrNull ?? const [];
    final technician = ref.watch(currentUserProvider).valueOrNull;
    return bookings.when(
      data: (items) {
        final active =
            items.where((b) => isTechnicianBusyStatus(b.status)).toList();
        final held =
            items.where((b) => b.status == BookingStatus.onHold).toList();
        final billing = items
            .where((b) =>
                b.status == BookingStatus.workCompletedPendingCustomer ||
                b.status == BookingStatus.serviceCompleted ||
                b.status == BookingStatus.billGenerated)
            .toList();
        final completed =
            items.where((b) => b.status == BookingStatus.closed).toList();
        final done = completed.length;
        final paidBills = bills.where((bill) => bill.isPaid).toList();
        double totalFor(bool Function(DateTime date) matches) => paidBills
            .where((bill) => matches(bill.revenueDate))
            .fold<double>(0, (sum, bill) => sum + bill.amount);
        final now = DateTime.now();
        final todayTotal = totalFor((date) =>
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day);
        final monthlyTotal = totalFor(
            (date) => date.year == now.year && date.month == now.month);
        final yearlyTotal = totalFor((date) => date.year == now.year);
        return LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth =
                constraints.maxWidth >= 1280 ? 1120.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: TabBar(
                          isScrollable: true,
                          labelColor: AppTheme.primary,
                          unselectedLabelColor: AppTheme.textSecondary,
                          indicatorColor: AppTheme.primary,
                          indicatorWeight: 3,
                          tabs: [
                            Tab(text: 'Assigned (${active.length})'),
                            Tab(text: 'Completed (${billing.length})'),
                            Tab(text: 'On hold (${held.length})'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: _HeroPanel(
                          active: active.length,
                          done: done,
                          technicianName: technician?.name ?? 'Technician',
                          nextAction: active.isEmpty
                              ? 'No active job right now'
                              : _technicianNextAction(active.first.status),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: LayoutBuilder(
                          builder: (context, metricConstraints) {
                            final compact = metricConstraints.maxWidth < 600;
                            final width = compact
                                ? (metricConstraints.maxWidth - 10) / 2
                                : 190.0;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: width,
                                  child: _MetricCard(
                                    label: 'Today earnings',
                                    value:
                                        'Rs. ${todayTotal.toStringAsFixed(0)}',
                                    width: double.infinity,
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _MetricCard(
                                    label: 'Monthly earnings',
                                    value:
                                        'Rs. ${monthlyTotal.toStringAsFixed(0)}',
                                    width: double.infinity,
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _MetricCard(
                                    label: 'Yearly earnings',
                                    value:
                                        'Rs. ${yearlyTotal.toStringAsFixed(0)}',
                                    width: double.infinity,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (overtime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: OvertimeSummaryPanel(
                            records: overtime,
                            bookings: items,
                            bills: bills,
                            title: 'Your overtime',
                          ),
                        ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _JobTabList(
                              bookings: active,
                              emptyTitle: 'No assigned jobs',
                              emptyMessage:
                                  'New assigned and active jobs will appear here.',
                            ),
                            _JobTabList(
                              bookings: billing,
                              emptyTitle: 'No completed jobs',
                              emptyMessage:
                                  'Customer confirmation and final bill collection will appear here.',
                            ),
                            _JobTabList(
                              bookings: held,
                              emptyTitle: 'No jobs on hold',
                              emptyMessage:
                                  'Jobs you place on hold will appear here. Your branch admin is notified automatically.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
    );
  }
}

class _JobHistoryView extends ConsumerWidget {
  const _JobHistoryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings =
        ref.watch(technicianBookingsProvider).valueOrNull ?? const <Booking>[];
    final completed = bookings
        .where((booking) => booking.status == BookingStatus.closed)
        .toList();
    return _JobTabList(
      bookings: completed,
      emptyTitle: 'No job history yet',
      emptyMessage: 'Paid and closed service jobs will appear here.',
    );
  }
}

class _JobTabList extends StatelessWidget {
  const _JobTabList({
    required this.bookings,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Booking> bookings;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EmptyJobsCard(
            title: emptyTitle,
            message: emptyMessage,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _TechnicianJobCard(
        booking: bookings[index],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.active,
    required this.done,
    required this.technicianName,
    required this.nextAction,
  });

  final int active;
  final int done;
  final String technicianName;
  final String nextAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good morning, ${technicianName.split(' ').first}',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          const Text('Today’s work',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Next: $nextAction',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _InlineMetric(label: 'Active', value: '$active'),
              const SizedBox(width: 10),
              _InlineMetric(label: 'Done', value: '$done'),
              const SizedBox(width: 10),
              const _InlineMetric(label: 'ETA alerts', value: 'Live'),
            ],
          ),
        ],
      ),
    );
  }
}

String _technicianNextAction(BookingStatus status) {
  return switch (status) {
    BookingStatus.technicianAssigned => 'Review and accept the assignment',
    BookingStatus.accepted => 'Review the issue and send an estimate',
    BookingStatus.estimateSent => 'Wait for customer estimate approval',
    BookingStatus.estimateApproved => 'Start your journey',
    BookingStatus.onTheWay => 'Confirm when you meet the customer',
    BookingStatus.arrived => 'Wait for customer meeting confirmation',
    BookingStatus.customerConfirmedArrival => 'Start the service work',
    BookingStatus.serviceStarted => 'Complete the service work',
    BookingStatus.workCompletedPendingCustomer =>
      'Wait for customer work confirmation',
    BookingStatus.serviceCompleted => 'Create the final bill',
    BookingStatus.billGenerated => 'Collect and confirm payment',
    BookingStatus.onHold => 'This job is on hold',
    BookingStatus.booked => 'Waiting for Branch Admin assignment',
    BookingStatus.estimateRejected => 'Update the estimate',
    BookingStatus.closed => 'No action needed',
  };
}

bool _canTechnicianPlaceOnHold(BookingStatus status) {
  return status != BookingStatus.booked &&
      status != BookingStatus.onHold &&
      status != BookingStatus.serviceCompleted &&
      status != BookingStatus.billGenerated &&
      status != BookingStatus.closed;
}

class _TechnicianJobCard extends ConsumerWidget {
  const _TechnicianJobCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    BookingRepository bookingRepository() =>
        ref.read(bookingRepositoryProvider);
    Future<bool> confirmAction(
      String title,
      String message,
      String action,
    ) async {
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(action),
                ),
              ],
            ),
          ) ??
          false;
    }

    Future<void> placeOnHold() async {
      final reason = TextEditingController();
      try {
        final submitted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Put job on hold'),
            content: TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason for hold',
                hintText: 'Example: Part needs to be collected',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (reason.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Put on hold'),
              ),
            ],
          ),
        );
        if (submitted != true || user == null) return;
        await bookingRepository().placeOnHold(
          bookingId: booking.id,
          actingTechnicianId: user.uid,
          reason: reason.text,
        );
        await ref.read(locationTrackingServiceProvider).finishBooking();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Job placed on hold. The customer and branch admin were notified.',
            ),
          ),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingOperationError(error)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } finally {
        reason.dispose();
      }
    }

    final estimate =
        ref.watch(technicianEstimateProvider(booking.id)).valueOrNull;
    final bill =
        ref.watch(technicianBookingBillProvider(booking.id)).valueOrNull;
    final technicianLocation = user == null
        ? null
        : ref.watch(technicianLiveLocationProvider(user.uid)).valueOrNull;
    final trackingThisBooking =
        technicianLocation?.activeBookingId == booking.id;
    final customerDistanceMeters =
        _distanceToCustomer(booking, technicianLocation);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                final appliance = Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _applianceIcon(booking.applianceType),
                    color: AppTheme.primary,
                  ),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.applianceType,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      booking.customerName,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      booking.problemDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          appliance,
                          const SizedBox(width: 12),
                          Expanded(child: details),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(booking.status.label),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    appliance,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    Chip(label: Text(booking.status.label)),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_forward_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Next: ${_technicianNextAction(booking.status)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (booking.status == BookingStatus.technicianAssigned) ...[
                  FilledButton.tonalIcon(
                    onPressed: user == null
                        ? null
                        : () async {
                            await bookingRepository().transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.technicianAssigned,
                              next: BookingStatus.accepted,
                            );
                            await ref
                                .read(locationTrackingServiceProvider)
                                .start(
                                  technicianId: user.uid,
                                  bookingId: booking.id,
                                  branchId: user.branchId,
                                );
                          },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Accept & track'),
                  ),
                  OutlinedButton.icon(
                    onPressed: user == null
                        ? null
                        : () => bookingRepository().rejectAssignment(
                              bookingId: booking.id,
                              technicianId: user.uid,
                            ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ],
                if (booking.status == BookingStatus.accepted)
                  FilledButton.icon(
                    onPressed: () => _showEstimateDialog(context, ref),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Review issue & create estimate'),
                  ),
                if (booking.status == BookingStatus.onTheWay &&
                    !trackingThisBooking)
                  FilledButton.tonalIcon(
                    onPressed: user == null
                        ? null
                        : () async {
                            try {
                              await ref
                                  .read(locationTrackingServiceProvider)
                                  .start(
                                    technicianId: user.uid,
                                    bookingId: booking.id,
                                    branchId: user.branchId,
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Live tracking resumed. Confirm arrival only when you reach the customer.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(userFacingOperationError(error)),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Resume tracking'),
                  ),
                if (booking.status == BookingStatus.onTheWay)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            if (!await confirmAction(
                              'Confirm arrival',
                              "Confirm that you have reached the customer's location.",
                              'I reached the customer',
                            )) {
                              return;
                            }
                            try {
                              final position =
                                  await _bestAvailableTechnicianPosition();
                              final distanceMeters = position == null
                                  ? customerDistanceMeters
                                  : _distanceToCustomerFromCoordinates(
                                      booking,
                                      position.latitude,
                                      position.longitude,
                                    );
                              await bookingRepository()
                                  .markTechnicianReachedCustomer(
                                bookingId: booking.id,
                                technicianId: user.uid,
                                technicianLatitude: position?.latitude ??
                                    technicianLocation?.latitude,
                                technicianLongitude: position?.longitude ??
                                    technicianLocation?.longitude,
                                distanceFromCustomerMeters: distanceMeters,
                                manualOverride: distanceMeters == null ||
                                    distanceMeters > 150 ||
                                    !trackingThisBooking,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Customer confirmation requested.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text(userFacingOperationError(error)),
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.person_pin_circle_outlined),
                    label: Text(
                      trackingThisBooking && customerDistanceMeters != null
                          ? 'I reached the customer (${_formatRouteDistance(customerDistanceMeters)})'
                          : 'I reached the customer',
                    ),
                  ),
                if (booking.status == BookingStatus.arrived)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Waiting for customer confirmation'),
                  ),
                if (booking.status == BookingStatus.customerConfirmedArrival)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            if (!await confirmAction(
                              'Start Work?',
                              'Both you and the customer confirmed the meeting. Start service now?',
                              'Start Work',
                            )) {
                              return;
                            }
                            await bookingRepository().transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.customerConfirmedArrival,
                              next: BookingStatus.serviceStarted,
                            );
                            await ref
                                .read(locationTrackingServiceProvider)
                                .finishBooking();
                          },
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('Start work'),
                  ),
                if (booking.status == BookingStatus.estimateSent)
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context, booking),
                    icon: const Icon(Icons.hourglass_top),
                    label: const Text('Waiting for customer approval'),
                  ),
                if (booking.status == BookingStatus.estimateRejected)
                  FilledButton.icon(
                    onPressed: () => _showEstimateDialog(context, ref),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Revise estimate'),
                  ),
                if (booking.status == BookingStatus.estimateApproved)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            if (!await confirmAction(
                              'Start Journey?',
                              'Your location will now be tracked while travelling to the customer.',
                              'Start Journey',
                            )) {
                              return;
                            }
                            await bookingRepository().transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.estimateApproved,
                              next: BookingStatus.onTheWay,
                            );
                            await ref
                                .read(locationTrackingServiceProvider)
                                .start(
                                  technicianId: user.uid,
                                  bookingId: booking.id,
                                  branchId: user.branchId,
                                );
                          },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start journey'),
                  ),
                if (booking.status == BookingStatus.serviceStarted)
                  FilledButton.icon(
                    onPressed: () async {
                      if (user == null) return;
                      if (!await confirmAction(
                        'Work Completed?',
                        'Confirm that the service work is completed. The customer must confirm next.',
                        'Confirm Work Completed',
                      )) {
                        return;
                      }
                      try {
                        await bookingRepository().requestWorkCompletion(
                          bookingId: booking.id,
                          technicianId: user.uid,
                        );
                        // Workday tracking stays active after a job finishes.
                        // Customer visibility ends with this booking, while
                        // Branch and Super Admin history continues until the
                        // technician explicitly closes today's work.
                        await ref
                            .read(locationTrackingServiceProvider)
                            .finishBooking();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completion sent to the customer for confirmation.',
                            ),
                          ),
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(userFacingOperationError(error)),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.done_all),
                    label: const Text('I completed the work'),
                  ),
                if (booking.status == BookingStatus.serviceCompleted &&
                    booking.customerConfirmedWorkCompletedAt == null)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            try {
                              await bookingRepository().requestWorkCompletion(
                                bookingId: booking.id,
                                technicianId: user.uid,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Completion sent to the customer for confirmation.',
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(userFacingOperationError(error)),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('I completed the work'),
                  ),
                if (booking.status ==
                    BookingStatus.workCompletedPendingCustomer)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.fact_check_outlined),
                    label:
                        const Text('Technician confirmed - waiting customer'),
                  ),
                if (booking.status == BookingStatus.onHold) ...[
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text(
                      booking.holdReason == null || booking.holdReason!.isEmpty
                          ? 'On hold'
                          : 'On hold: ${booking.holdReason}',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            if (!await confirmAction(
                              'Resume this job?',
                              'The customer will be notified that the service has resumed.',
                              'Resume job',
                            )) {
                              return;
                            }
                            try {
                              await bookingRepository().resumeFromHold(
                                bookingId: booking.id,
                                actingTechnicianId: user.uid,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Job resumed. Customer notified.'),
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(userFacingOperationError(error)),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Resume job'),
                  ),
                ] else if (_canTechnicianPlaceOnHold(booking.status))
                  OutlinedButton.icon(
                    onPressed: user == null ? null : placeOnHold,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Put job on hold'),
                  ),
                if (booking.status == BookingStatus.serviceCompleted &&
                    booking.customerConfirmedWorkCompletedAt != null)
                  FilledButton.icon(
                    onPressed: user == null || estimate == null
                        ? null
                        : () => _showFinalBillDialog(
                              context,
                              ref,
                              booking,
                              estimate,
                            ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Generate bill'),
                  ),
                if (booking.status == BookingStatus.billGenerated &&
                    bill != null) ...[
                  if (bill.isPaid)
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.verified_outlined),
                      label:
                          Text('Payment confirmed - ${bill.paymentModeLabel}'),
                    )
                  else if (bill.hasPaymentForApproval)
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_top),
                      label: Text(
                        'Receipt recorded - waiting for customer',
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: user == null
                          ? null
                          : () => _showPaymentDialog(
                                context: context,
                                ref: ref,
                                booking: booking,
                                technicianId: user.uid,
                                bill: bill,
                              ),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Confirm payment ${_formatBillAmount(bill)}'),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if ((booking.imageUrl ?? '').trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.photo_outlined, size: 18),
                        SizedBox(width: 7),
                        Text(
                          'Customer appliance photo',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        booking.imageUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 100,
                          child: Center(
                            child: Text(
                              'Photo could not be loaded. Check access rules and try again.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: (booking.imageUrl ?? '').trim().isNotEmpty
                  ? FilledButton.tonalIcon(
                      onPressed: () => context.push('/booking/${booking.id}'),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('View customer photo'),
                    )
                  : OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.no_photography_outlined),
                      label: const Text('No customer photo attached'),
                    ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              leading: const Icon(Icons.route_outlined),
              title: const Text('Trip, contact and service details'),
              children: [
                _InfoRow(
                  icon: Icons.place_outlined,
                  text: booking.address,
                  actionLabel: 'Directions',
                  onAction: () => _openDirections(context, booking),
                ),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  text: booking.phone,
                  actionLabel: 'WhatsApp',
                  onAction: () => _openWhatsApp(context, booking),
                ),
                _InfoRow(
                  icon: Icons.schedule,
                  text: 'Preferred time: ${booking.preferredTime}',
                ),
                const SizedBox(height: 8),
                _TechnicianJobMap(
                  booking: booking,
                  technicianLocation: technicianLocation,
                  onDirections: () => _openDirections(context, booking),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((booking.imageUrl ?? '').trim().isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => Dialog(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Customer appliance photo',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext).pop(),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 420,
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        booking.imageUrl!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(
                                          height: 180,
                                          child: Center(
                                            child: Text(
                                              'Customer photo could not be loaded.',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('View customer photo'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.no_photography_outlined),
                        label: const Text('No customer photo attached'),
                      ),
                    if (booking.status ==
                        BookingStatus.customerConfirmedArrival)
                      OutlinedButton.icon(
                        onPressed: () =>
                            _uploadServicePhoto(context, ref, 'before'),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Before photo'),
                      ),
                    if (booking.status == BookingStatus.serviceStarted) ...[
                      OutlinedButton.icon(
                        onPressed: () =>
                            _uploadServicePhoto(context, ref, 'during'),
                        icon: const Icon(Icons.camera_outlined),
                        label: const Text('During photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _uploadServicePhoto(context, ref, 'after'),
                        icon: const Icon(Icons.camera_enhance_outlined),
                        label: const Text('After photo'),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: () => context.push('/booking/${booking.id}'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Full booking details'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFinalBillDialog(
    BuildContext context,
    WidgetRef ref,
    Booking booking,
    Estimate estimate,
  ) async {
    final labour = TextEditingController(
      text: estimate.labourCharge.toStringAsFixed(0),
    );
    final parts = TextEditingController(
      text: estimate.partsCharge.toStringAsFixed(0),
    );
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create final bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approved estimate: ₹${estimate.total.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the actual on-site charges. GST is added separately at 9% CGST + 9% SGST.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labour,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(labelText: 'Actual labour charge'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: parts,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(labelText: 'Actual parts charge'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for any change from estimate',
                hintText: 'Required if final charges differ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final labourValue = double.tryParse(labour.text.trim());
              final partsValue = double.tryParse(parts.text.trim());
              final total = (labourValue ?? 0) + (partsValue ?? 0);
              final differsFromEstimate =
                  (total - estimate.total).abs() > 0.009;
              if (labourValue == null ||
                  partsValue == null ||
                  labourValue < 0 ||
                  partsValue < 0 ||
                  total <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter valid final charges.')),
                );
                return;
              }
              if (differsFromEstimate && reason.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Explain why the final charges changed.'),
                  ),
                );
                return;
              }
              final user = ref.read(currentUserProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref.read(billRepositoryProvider).generateBill(
                      bookingId: booking.id,
                      customerId: booking.customerId,
                      technicianId: user.uid,
                      labourCharge: labourValue,
                      partsCharge: partsValue,
                      adjustmentReason:
                          differsFromEstimate ? reason.text.trim() : null,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Final bill generated. You can now confirm payment.',
                    ),
                  ),
                );
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(userFacingOperationError(error)),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: const Text('Generate final bill'),
          ),
        ],
      ),
    );
    labour.dispose();
    parts.dispose();
    reason.dispose();
  }

  Future<void> _showEstimateDialog(BuildContext context, WidgetRef ref) async {
    final labour = TextEditingController();
    final parts = TextEditingController();
    final notes = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate cost estimate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: labour,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Labour charge')),
            const SizedBox(height: 12),
            TextField(
                controller: parts,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Parts charge')),
            const SizedBox(height: 12),
            TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Work notes')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider).valueOrNull;
              final labourValue = double.tryParse(labour.text);
              final partsValue = double.tryParse(parts.text);
              if (user == null ||
                  labourValue == null ||
                  partsValue == null ||
                  labourValue < 0 ||
                  partsValue < 0 ||
                  labourValue + partsValue <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid non-negative estimate charges.'),
                  ),
                );
                return;
              }
              await ref.read(estimateRepositoryProvider).createEstimate(
                    Estimate(
                      id: '',
                      bookingId: booking.id,
                      technicianId: user.uid,
                      labourCharge: labourValue,
                      partsCharge: partsValue,
                      notes: notes.text.trim(),
                      isApproved: false,
                      createdAt: DateTime.now(),
                    ),
                  );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Estimate sent in app. Customer can approve it from the booking details screen.')),
                );
              }
            },
            child: const Text('Send estimate'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPaymentDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Booking booking,
    required String technicianId,
    required Bill bill,
  }) async {
    var selectedMode = 'cash';
    final amount = TextEditingController(text: bill.amount.toStringAsFixed(0));
    XFile? proof;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Confirm customer payment'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount received'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedMode,
                decoration: const InputDecoration(
                  labelText: 'Mode of payment',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(
                    value: 'bankTransfer',
                    child: Text('Bank transfer'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedMode = value;
                    if (value == 'cash') proof = null;
                  });
                },
              ),
              if (selectedMode != 'cash') ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (image != null) setDialogState(() => proof = image);
                  },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(proof == null
                      ? 'Upload payment screenshot'
                      : 'Screenshot selected'),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final received = double.tryParse(amount.text.trim());
                if (received == null || received <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Enter a valid amount received.')),
                  );
                  return;
                }
                if (selectedMode != 'cash' && proof == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Upload the online payment screenshot.')),
                  );
                  return;
                }
                String? proofUrl;
                if (proof != null) {
                  proofUrl = await ref
                      .read(cloudinaryRepositoryProvider)
                      .uploadPaymentProof(
                        file: proof!,
                        bookingId: booking.id,
                      );
                }
                await ref.read(billRepositoryProvider).confirmCollectedPayment(
                      bookingId: booking.id,
                      technicianId: technicianId,
                      paymentMode: selectedMode,
                      amountReceived: received,
                      paymentProofUrl: proofUrl,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Payment received recorded. Waiting for customer confirmation.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Confirm payment received'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadServicePhoto(
      BuildContext context, WidgetRef ref, String stage) async {
    XFile? image;

    if (kIsWeb) {
      // On web, camera source is unreliable - use gallery (file picker) instead.
      image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 75);
    } else {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () =>
                      Navigator.pop(sheetContext, ImageSource.gallery)),
            ],
          ),
        ),
      );
      if (source == null) return;
      image = await ImagePicker().pickImage(source: source, imageQuality: 75);
    }

    if (image == null) return;

    final url = await ref.read(storageRepositoryProvider).uploadXFile(
          file: image,
          folder: 'bookings/${booking.id}/$stage',
          fileName: '${const Uuid().v4()}.jpg',
        );
    await ref
        .read(bookingRepositoryProvider)
        .addServicePhoto(bookingId: booking.id, stage: stage, url: url);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$stage service photo uploaded')));
    }
  }

  Future<void> _openDirections(BuildContext context, Booking booking) async {
    final destination = booking.latitude != null && booking.longitude != null
        ? '${booking.latitude},${booking.longitude}'
        : booking.address;
    String? origin;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));
      origin = '${position.latitude},${position.longitude}';
    } catch (_) {
      origin = null;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (origin != null) 'origin': origin,
      'destination': destination,
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Google Maps directions')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context, Booking booking) async {
    final phone = booking.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final text =
        'FixNow technician update for ${booking.applianceType}: we are working on your service request.';
    final uri =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp could not be opened')),
      );
    }
  }
}

class _AttendanceView extends ConsumerStatefulWidget {
  const _AttendanceView();

  @override
  ConsumerState<_AttendanceView> createState() => _AttendanceViewState();
}

class _TechnicianJobMap extends ConsumerWidget {
  const _TechnicianJobMap({
    required this.booking,
    required this.technicianLocation,
    required this.onDirections,
  });

  final Booking booking;
  final TechnicianLocation? technicianLocation;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approximatePin = booking.latitude == null || booking.longitude == null
        ? ref.watch(technicianAddressPinProvider(booking.address))
        : null;
    final serviceLatitude =
        booking.latitude ?? approximatePin?.valueOrNull?.latitude;
    final serviceLongitude =
        booking.longitude ?? approximatePin?.valueOrNull?.longitude;
    final usingApproximatePin =
        booking.latitude == null && approximatePin?.valueOrNull != null;

    if (serviceLatitude == null || serviceLongitude == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 168),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, color: AppTheme.primary, size: 30),
            const SizedBox(height: 8),
            const Text(
              'Exact map pin is not available for this booking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              booking.address,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            if (approximatePin?.isLoading == true)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              OutlinedButton.icon(
                onPressed: onDirections,
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Open directions'),
              ),
          ],
        ),
      );
    }

    final customerPoint = GoogleMapPoint(
      latitude: serviceLatitude,
      longitude: serviceLongitude,
      label: 'C',
      color: usingApproximatePin ? const Color(0xFFF08C00) : AppTheme.accent,
      icon: usingApproximatePin
          ? Icons.location_searching
          : Icons.home_repair_service_outlined,
    );
    final techPoint = technicianLocation == null
        ? null
        : GoogleMapPoint(
            latitude: technicianLocation!.latitude,
            longitude: technicianLocation!.longitude,
            label: 'T',
            color: AppTheme.primary,
            icon: Icons.engineering_outlined,
            bearing: technicianLocation!.bearing,
          );
    final trackingActive = technicianLocation?.activeBookingId == booking.id;
    final gpsIsStale = technicianLocation != null &&
        isGpsUpdateStale(technicianLocation!.updatedAt);
    final trackingLabel = _technicianMapStatusLabel(
      status: booking.status,
      hasTechnicianLocation: techPoint != null,
      trackingActive: trackingActive,
      gpsIsStale: gpsIsStale,
    );
    final points = [
      if (techPoint != null) techPoint,
      customerPoint,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RoadRouteMap(
                  points: points,
                  origin: gpsIsStale ? null : techPoint,
                  destination: customerPoint,
                  zoom: techPoint == null ? 15 : 13,
                  badge: gpsIsStale
                      ? 'GPS stale'
                      : usingApproximatePin
                          ? 'Approx route'
                          : 'Live route',
                  noOriginLabel: usingApproximatePin
                      ? 'Approximate pin shown'
                      : 'Customer pin shown',
                  showRouteSummary: booking.status != BookingStatus.arrived,
                  showRouteLine: booking.status != BookingStatus.arrived,
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: _MapStatusPill(
                    label: trackingLabel,
                    color: usingApproximatePin
                        ? const Color(0xFFF08C00)
                        : AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _showInAppNavigation(
                  context: context,
                  booking: booking,
                  technicianLocation: technicianLocation,
                  destinationLatitude: serviceLatitude,
                  destinationLongitude: serviceLongitude,
                  onExternalDirections: onDirections,
                ),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Route guidance'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onDirections,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Maps'),
            ),
          ],
        ),
      ],
    );
  }

  void _showInAppNavigation({
    required BuildContext context,
    required Booking booking,
    required TechnicianLocation? technicianLocation,
    required double destinationLatitude,
    required double destinationLongitude,
    required VoidCallback onExternalDirections,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _InAppNavigationSheet(
        booking: booking,
        technicianLocation: technicianLocation,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        onExternalDirections: onExternalDirections,
      ),
    );
  }
}

class _InAppNavigationSheet extends ConsumerStatefulWidget {
  const _InAppNavigationSheet({
    required this.booking,
    required this.technicianLocation,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.onExternalDirections,
  });

  final Booking booking;
  final TechnicianLocation? technicianLocation;
  final double destinationLatitude;
  final double destinationLongitude;
  final VoidCallback onExternalDirections;

  @override
  ConsumerState<_InAppNavigationSheet> createState() =>
      _InAppNavigationSheetState();
}

class _InAppNavigationSheetState extends ConsumerState<_InAppNavigationSheet> {
  RoadRouteSummary? _routeSummary;
  bool _recoveringGps = false;
  String? _gpsRecoveryMessage;

  Future<void> _recoverGps() async {
    if (_recoveringGps) return;
    setState(() {
      _recoveringGps = true;
      _gpsRecoveryMessage = null;
    });
    try {
      final service = ref.read(locationTrackingServiceProvider);
      var recovered = await service.recoverNow();
      if (!recovered) {
        final user = ref.read(currentUserProvider).valueOrNull;
        if (user != null) {
          await service.start(
            technicianId: user.uid,
            bookingId: widget.booking.id,
            branchId: user.branchId,
          );
          recovered = true;
        }
      }
      if (mounted) {
        setState(() {
          _gpsRecoveryMessage = recovered
              ? 'Fresh GPS fix received. Route is recalculating.'
              : 'GPS is still unavailable. Check location services.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsRecoveryMessage =
              'GPS recovery failed. Check location permission and signal.';
        });
      }
    } finally {
      if (mounted) setState(() => _recoveringGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final location = widget.technicianLocation == null
        ? null
        : ref
                .watch(
                  technicianLiveLocationProvider(
                    widget.technicianLocation!.technicianId,
                  ),
                )
                .valueOrNull ??
            widget.technicianLocation;
    final customerPoint = GoogleMapPoint(
      latitude: widget.destinationLatitude,
      longitude: widget.destinationLongitude,
      label: 'D',
      color: AppTheme.accent,
      icon: Icons.home_repair_service_outlined,
    );
    final techPoint = location == null
        ? null
        : GoogleMapPoint(
            latitude: location.latitude,
            longitude: location.longitude,
            label: 'T',
            color: AppTheme.primary,
            icon: Icons.navigation_outlined,
            bearing: location.bearing,
          );
    final isArrived = booking.status == BookingStatus.arrived;
    final gpsIsStale = location == null || isGpsUpdateStale(location.updatedAt);
    final speed = location?.speed == null
        ? '0 km/h'
        : '${(location!.speed! * 3.6).round()} km/h';

    final sheetHeight = MediaQuery.sizeOf(context).height * 0.92;
    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isArrived ? 'Arrived at customer' : 'In-app navigation',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _NavigationHeader(
              status: isArrived
                  ? 'Technician has arrived'
                  : gpsIsStale
                      ? 'GPS update is stale'
                      : _routeSummary == null
                          ? 'Finding best road route'
                          : 'Technician is arriving',
              eta: isArrived ? 'Arrived' : _routeSummary?.durationLabel,
              arrivalTime: isArrived || _routeSummary == null
                  ? null
                  : DateFormat.jm().format(
                      _routeSummary!.estimatedArrival(),
                    ),
              distance: _routeSummary?.distanceLabel,
              speed: speed,
              updatedAt: location?.updatedAt,
              routeProvider: _routeSummary?.providerLabel,
              gpsIsStale: gpsIsStale,
              isRecoveringGps: _recoveringGps,
              gpsRecoveryMessage: _gpsRecoveryMessage,
              onRecoverGps: _recoverGps,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RoadRouteMap(
                        points: [
                          if (techPoint != null) techPoint,
                          customerPoint,
                        ],
                        origin: gpsIsStale ? null : techPoint,
                        destination: customerPoint,
                        zoom: 17,
                        badge: 'Navigation',
                        noOriginLabel: gpsIsStale
                            ? 'GPS stale - route paused'
                            : 'Waiting for technician GPS',
                        showRouteLine: !isArrived,
                        showRouteSummary: false,
                        onRouteUpdated: (summary) {
                          if (!mounted || summary == _routeSummary) return;
                          setState(() => _routeSummary = summary);
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: _DirectionsPanel(
                    steps: _routeSummary?.steps ?? const [],
                    destinationAddress: widget.booking.address,
                    gpsIsStale: gpsIsStale,
                    routeLoaded: _routeSummary != null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Back to job'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: widget.onExternalDirections,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Google Maps'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStatusPill extends StatelessWidget {
  const _MapStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_repair_service_outlined, color: color, size: 16),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionsPanel extends StatelessWidget {
  const _DirectionsPanel({
    required this.steps,
    required this.destinationAddress,
    required this.gpsIsStale,
    required this.routeLoaded,
  });

  final List<RoadRouteStep> steps;
  final String destinationAddress;
  final bool gpsIsStale;
  final bool routeLoaded;

  @override
  Widget build(BuildContext context) {
    final visibleSteps = steps.take(8).toList(growable: false);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Turn-by-turn guidance',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (steps.length > visibleSteps.length)
                Text(
                  '+${steps.length - visibleSteps.length}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (gpsIsStale)
            const _GuidanceMessage(
              icon: Icons.gps_off_outlined,
              text: 'Refresh GPS to resume live directions.',
            )
          else if (!routeLoaded)
            const _GuidanceMessage(
              icon: Icons.route_outlined,
              text: 'Finding the best road route...',
            )
          else if (visibleSteps.isEmpty)
            _GuidanceMessage(
              icon: Icons.flag_outlined,
              text:
                  'Route is ready. Continue to the customer address: $destinationAddress',
            )
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: visibleSteps.length,
                separatorBuilder: (_, __) => const Divider(height: 14),
                itemBuilder: (context, index) => _DirectionStepTile(
                  step: visibleSteps[index],
                  index: index,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuidanceMessage extends StatelessWidget {
  const _GuidanceMessage({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionStepTile extends StatelessWidget {
  const _DirectionStepTile({
    required this.step,
    required this.index,
  });

  final RoadRouteStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: index == 0
              ? AppTheme.primary
              : AppTheme.primary.withValues(alpha: 0.10),
          child: Icon(
            _directionIcon(step),
            size: 17,
            color: index == 0 ? Colors.white : AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.instruction,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (step.distanceLabel.isNotEmpty)
                    Text(
                      step.distanceLabel,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  if (step.durationLabel.isNotEmpty)
                    Text(
                      step.durationLabel,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  if (step.roadName != null && step.roadName!.isNotEmpty)
                    Text(
                      'via ${step.roadName}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _directionIcon(RoadRouteStep step) {
    final text = '${step.maneuver ?? ''} ${step.instruction}'.toLowerCase();
    if (text.contains('arrive')) return Icons.flag_outlined;
    if (text.contains('left')) return Icons.turn_left;
    if (text.contains('right')) return Icons.turn_right;
    if (text.contains('roundabout')) return Icons.roundabout_right;
    if (text.contains('merge') || text.contains('ramp')) {
      return Icons.ramp_right;
    }
    return Icons.straight;
  }
}

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader({
    required this.status,
    required this.eta,
    required this.arrivalTime,
    required this.distance,
    required this.speed,
    required this.updatedAt,
    required this.routeProvider,
    required this.gpsIsStale,
    required this.isRecoveringGps,
    required this.gpsRecoveryMessage,
    required this.onRecoverGps,
  });

  final String status;
  final String? eta;
  final String? arrivalTime;
  final String? distance;
  final String speed;
  final DateTime? updatedAt;
  final String? routeProvider;
  final bool gpsIsStale;
  final bool isRecoveringGps;
  final String? gpsRecoveryMessage;
  final VoidCallback onRecoverGps;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            if (gpsIsStale) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFFFB4AB)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.gps_off_outlined,
                      color: Color(0xFFB3261E),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The last GPS point is over 90 seconds old. Navigation will resume after a fresh fix.',
                        style: TextStyle(
                          color: Color(0xFF8C1D18),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isRecoveringGps ? null : onRecoverGps,
                      icon: isRecoveringGps
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh GPS'),
                    ),
                  ],
                ),
              ),
            ],
            if (gpsRecoveryMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                gpsRecoveryMessage!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _NavigationChip(
                  icon: Icons.timer_outlined,
                  label: eta == null
                      ? 'ETA loading'
                      : eta == 'Arrived'
                          ? 'Arrived'
                          : '$eta away',
                ),
                if (arrivalTime != null)
                  _NavigationChip(
                    icon: Icons.schedule_outlined,
                    label: 'Arrive by $arrivalTime',
                  ),
                _NavigationChip(
                  icon: Icons.route_outlined,
                  label: distance ?? 'Route loading',
                ),
                _NavigationChip(
                  icon: Icons.speed_outlined,
                  label: speed,
                ),
                if (updatedAt != null)
                  _NavigationChip(
                    icon: Icons.update,
                    label: _trackingUpdatedLabel(updatedAt!),
                  ),
                if (routeProvider != null)
                  _NavigationChip(
                    icon: Icons.map_outlined,
                    label: '$routeProvider route',
                  ),
                const _NavigationChip(
                  icon: Icons.my_location,
                  label: 'Current location',
                ),
                const _NavigationChip(
                  icon: Icons.location_on_outlined,
                  label: 'Destination',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationChip extends StatelessWidget {
  const _NavigationChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primary, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _trackingUpdatedLabel(DateTime updatedAt) {
  final difference = DateTime.now().difference(updatedAt);
  if (difference.inSeconds < 45) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return DateFormat('dd MMM, hh:mm a').format(updatedAt);
}

String _technicianMapStatusLabel({
  required BookingStatus status,
  required bool hasTechnicianLocation,
  required bool trackingActive,
  bool gpsIsStale = false,
}) {
  if (gpsIsStale) return 'GPS stale - refresh navigation';
  if (status == BookingStatus.arrived) return 'Arrived at customer location';
  if (status == BookingStatus.customerConfirmedArrival) {
    return 'Arrival confirmed';
  }
  if (status.index >= BookingStatus.estimateSent.index) {
    return hasTechnicianLocation
        ? 'Technician location saved'
        : 'Customer location';
  }
  if (trackingActive) return 'Live route active';
  if (hasTechnicianLocation) return 'Last known route';
  if (status == BookingStatus.accepted) {
    return 'Tap Start journey for live route';
  }
  return 'Customer location';
}

double? _distanceToCustomer(
  Booking booking,
  TechnicianLocation? technicianLocation,
) {
  if (booking.latitude == null ||
      booking.longitude == null ||
      technicianLocation == null) {
    return null;
  }
  return Geolocator.distanceBetween(
    technicianLocation.latitude,
    technicianLocation.longitude,
    booking.latitude!,
    booking.longitude!,
  );
}

double? _distanceToCustomerFromCoordinates(
  Booking booking,
  double latitude,
  double longitude,
) {
  if (booking.latitude == null || booking.longitude == null) return null;
  return Geolocator.distanceBetween(
    latitude,
    longitude,
    booking.latitude!,
    booking.longitude!,
  );
}

Future<Position?> _bestAvailableTechnicianPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  }
}

String _formatRouteDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

class _AttendanceViewState extends ConsumerState<_AttendanceView> {
  bool _loading = false;
  bool _enrolling = false;
  bool _marked = false;
  String? _result;
  bool _usingLocalTestPosition = false;
  bool _attendanceStarted = false;
  int _attendanceStep = 1;
  XFile? _attendanceSelfie;
  Uint8List? _attendanceSelfieBytes;
  Position? _attendanceLocation;
  FaceMatchResult? _attendanceFaceMatch;

  void _setViewState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  Future<void> _startPresentFlow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Attendance'),
        content: const Text(
          'You are marking yourself as Present for today.\n\nComplete selfie and location verification next. Your location will be shared with FixNow after final confirmation.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm & Continue'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _setViewState(() {
        _attendanceStarted = true;
        _result = 'Take a selfie to begin verification.';
      });
    }
  }

  Future<void> _captureAttendanceSelfie() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final referenceSignature = user?.faceReferenceSignature?.trim() ?? '';
    if (referenceSignature.isEmpty) {
      _setViewState(() => _result =
          'Register your Face ID reference before taking attendance.');
      return;
    }
    _setViewState(() {
      _loading = true;
      _result = 'Opening camera...';
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 45,
        maxWidth: 640,
        maxHeight: 640,
      );
      if (image == null) {
        _setViewState(() => _result = 'Selfie capture cancelled.');
        return;
      }
      final bytes = await image.readAsBytes().timeout(
            const Duration(seconds: 12),
          );
      final faceService = const FaceMatchService();
      final signature = await faceService.createSignature(bytes);
      final match = faceService.compare(
        referenceSignature: referenceSignature,
        selfieSignature: signature,
      );
      if (!match.passed) {
        _setViewState(() {
          _attendanceSelfie = null;
          _attendanceSelfieBytes = null;
          _attendanceFaceMatch = null;
          _result =
              'Face could not be verified. Position your face clearly and retake the selfie.';
        });
        return;
      }
      _setViewState(() {
        _attendanceSelfie = image;
        _attendanceSelfieBytes = bytes;
        _attendanceFaceMatch = match;
        _attendanceStep = 2;
        _result = 'Selfie verified. Continue to location verification.';
      });
    } catch (error) {
      _setViewState(() => _result = _selfieFailureMessage(
            error,
            fallback: 'Selfie verification failed. Please retake it.',
          ));
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<void> _verifyAttendanceLocation() async {
    final config = ref.read(operationsConfigProvider).valueOrNull;
    if (config == null) {
      _setViewState(() => _result = 'Attendance settings are still loading.');
      return;
    }
    _setViewState(() {
      _loading = true;
      _result = 'Detecting current location...';
    });
    try {
      final position = await _attendancePosition(config);
      if (position == null) {
        _setViewState(() => _result =
            'Location could not be obtained. Enable precise location permission and retry.');
        return;
      }
      _setViewState(() {
        _attendanceLocation = position;
        _attendanceStep = 3;
        _result = 'Location detected. Review and confirm attendance.';
      });
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<void> _confirmStagedAttendance() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final config = ref.read(operationsConfigProvider).valueOrNull;
    final image = _attendanceSelfie;
    final bytes = _attendanceSelfieBytes;
    final position = _attendanceLocation;
    final match = _attendanceFaceMatch;
    if (user == null ||
        config == null ||
        image == null ||
        bytes == null ||
        position == null ||
        match == null ||
        !match.passed) {
      _setViewState(() => _result =
          'Complete selfie and location verification before confirming.');
      return;
    }
    _setViewState(() {
      _loading = true;
      _result = 'Recording attendance...';
    });
    try {
      final now = DateTime.now();
      final status = now.isAfter(config.endFor(now)) ? 'late' : 'present';
      final distance = Geolocator.distanceBetween(
        config.branchLatitude,
        config.branchLongitude,
        position.latitude,
        position.longitude,
      );
      final selfieUrl = await _uploadAttendanceSelfie(
        image: image,
        bytes: bytes,
        userId: user.uid,
        dayKey: _attendanceStorageDayKey(now),
      );
      await ref.read(technicianRepositoryProvider).markAttendance(
            Attendance(
              id: '',
              technicianId: user.uid,
              selfieUrl: selfieUrl,
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: now,
              status: status,
              faceMatchPassed: true,
              geofencePassed: distance <= config.geofenceRadiusMeters,
              faceMatchScore: match.score,
              branchId: user.branchId,
              locationSource:
                  _usingLocalTestPosition ? 'localTestFallback' : 'deviceGps',
            ),
          );
      try {
        final activeBooking = findTechnicianActiveBooking(
          ref.read(technicianBookingsProvider).valueOrNull ?? const <Booking>[],
          user.uid,
        );
        await ref.read(locationTrackingServiceProvider).startShift(
              technicianId: user.uid,
              branchId: user.branchId ?? '',
              bookingId: activeBooking?.id,
            );
      } catch (_) {}
      _setViewState(() {
        _marked = true;
        _result = 'Attendance recorded successfully.';
      });
    } catch (error) {
      _setViewState(() => _result = _selfieFailureMessage(
            error,
            fallback: 'Attendance could not be recorded. Please retry.',
          ));
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Leave'),
        content: const Text(
          'You are marking yourself as absent for today.\n\nThis will be recorded and visible to your Branch Admin.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    _setViewState(() => _loading = true);
    try {
      await ref.read(technicianRepositoryProvider).markAttendance(
            Attendance(
              id: '',
              technicianId: user.uid,
              selfieUrl: '',
              latitude: 0,
              longitude: 0,
              timestamp: DateTime.now(),
              status: 'absent',
              faceMatchPassed: false,
              geofencePassed: false,
              branchId: user.branchId,
              locationSource: 'leaveConfirmation',
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave Recorded Successfully')),
      );
    } catch (error) {
      _setViewState(() => _result = userFacingOperationError(error));
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<void> _enrollFace() async {
    _setViewState(() {
      _enrolling = true;
      _result = 'Opening reference selfie picker...';
    });
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) {
        _setViewState(() => _result = 'Not signed in.');
        return;
      }
      final image = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 45,
        maxWidth: 640,
        maxHeight: 640,
      );
      if (!mounted) return;
      if (image == null) {
        _setViewState(() => _result = 'No reference selfie selected.');
        return;
      }
      _setViewState(() => _result = 'Creating your Face ID reference...');
      final bytes = await image.readAsBytes().timeout(
            const Duration(seconds: 12),
          );
      if (!mounted) return;
      final faceService = const FaceMatchService();
      final signature = await faceService.createSignature(bytes);
      if (!mounted) return;
      // The matching signature is sufficient for later verification. Keeping
      // the full reference image out of the user document prevents every
      // technician-directory listener from downloading large profile records.
      _setViewState(() => _result = 'Saving your Face ID reference...');
      if (!mounted) return;
      await ref.read(authRepositoryProvider).updateFaceReference(
            uid: user.uid,
            photoUrl: '',
            signature: signature,
          );
      _setViewState(() {
        _result = 'Face ID reference saved. You can mark attendance now.';
      });
    } catch (e) {
      _setViewState(() {
        _result = _selfieFailureMessage(
          e,
          fallback: 'Face ID reference was not saved. Please try again.',
        );
      });
    } finally {
      _setViewState(() => _enrolling = false);
    }
  }

  // Retained temporarily for backward-compatible attendance recovery records.
  // ignore: unused_element
  Future<void> _markAttendance() async {
    _setViewState(() {
      _loading = true;
      _result = 'Opening selfie picker...';
    });
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) {
        _setViewState(() => _result = 'Not signed in.');
        return;
      }
      final referenceSignature = user.faceReferenceSignature?.trim() ?? '';
      if (referenceSignature.isEmpty) {
        _setViewState(() {
          _result =
              'Register your Face ID reference selfie before marking attendance.';
        });
        return;
      }
      final config = ref.read(operationsConfigProvider).valueOrNull;
      if (config == null) {
        _setViewState(() {
          _result = 'Attendance timing is still loading. Please try again.';
        });
        return;
      }
      final now = DateTime.now();
      final attendanceEnd = config.endFor(now);
      final attendanceStatus = now.isAfter(attendanceEnd) ? 'late' : 'present';
      final attendanceStatusLabel =
          attendanceStatus == 'late' ? 'Late' : 'Present';

      _setViewState(() => _result = 'Checking attendance location...');
      final position = await _attendancePosition(config);
      if (!mounted) return;
      if (position == null) {
        _setViewState(() {
          _result = kIsWeb
              ? 'Allow location for this site in the browser, then tap Upload selfie photo again.'
              : 'Enable precise location permission, then tap Take selfie again.';
        });
        return;
      }

      final image = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 45,
        maxWidth: 640,
        maxHeight: 640,
      );

      if (!mounted) return;
      if (image == null) {
        _setViewState(() => _result = 'No photo selected. Please try again.');
        return;
      }

      _setViewState(() => _result = 'Matching selfie with your Face ID...');
      final bytes = await image.readAsBytes().timeout(
            const Duration(seconds: 12),
          );
      if (!mounted) return;
      final distanceFromBranch = Geolocator.distanceBetween(
        config.branchLatitude,
        config.branchLongitude,
        position.latitude,
        position.longitude,
      );
      final geofencePassed = distanceFromBranch <= config.geofenceRadiusMeters;
      final faceService = const FaceMatchService();
      final selfieSignature = await faceService.createSignature(bytes);
      if (!mounted) return;
      final match = faceService.compare(
        referenceSignature: referenceSignature,
        selfieSignature: selfieSignature,
      );
      _setViewState(() => _result = 'Uploading attendance selfie...');
      final dayKey = _attendanceStorageDayKey(now);
      final selfieUrl = await _uploadAttendanceSelfie(
        image: image,
        bytes: bytes,
        userId: user.uid,
        dayKey: dayKey,
      );
      if (!mounted) return;
      if (!match.passed) {
        await ref.read(technicianRepositoryProvider).markAttendance(
              Attendance(
                id: '',
                technicianId: user.uid,
                selfieUrl: selfieUrl,
                latitude: position.latitude,
                longitude: position.longitude,
                timestamp: now,
                status: 'face_failed',
                faceMatchPassed: false,
                geofencePassed: geofencePassed,
                faceMatchScore: match.score,
                branchId: user.branchId,
                locationSource:
                    _usingLocalTestPosition ? 'localTestFallback' : 'deviceGps',
              ),
            );
        _setViewState(() {
          _result = 'Face ID did not match. Admin can see this failed attempt.';
        });
        return;
      }

      _setViewState(() => _result = 'Face ID matched. Saving attendance...');
      await ref.read(technicianRepositoryProvider).markAttendance(
            Attendance(
              id: '',
              technicianId: user.uid,
              selfieUrl: selfieUrl,
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: now,
              status: attendanceStatus,
              faceMatchPassed: true,
              geofencePassed: geofencePassed,
              faceMatchScore: match.score,
              branchId: user.branchId,
              locationSource:
                  _usingLocalTestPosition ? 'localTestFallback' : 'deviceGps',
            ),
          );

      var trackingMessage = ' Live location is now shared automatically.';
      try {
        final activeBooking = findTechnicianActiveBooking(
          ref.read(technicianBookingsProvider).valueOrNull ?? const <Booking>[],
          user.uid,
        );
        await ref.read(locationTrackingServiceProvider).startShift(
              technicianId: user.uid,
              branchId: user.branchId ?? '',
              bookingId: activeBooking?.id,
            );
      } catch (error) {
        trackingMessage =
            ' Attendance was saved, but location permission is still required.';
      }

      _setViewState(() {
        _marked = true;
        final locationNote =
            _usingLocalTestPosition ? ' Localhost test location was used.' : '';
        _result =
            '$attendanceStatusLabel marked for today. Face ID score ${(match.score * 100).round()}%.$locationNote$trackingMessage';
      });
    } catch (e) {
      _setViewState(() {
        _marked = false;
        _result = _selfieFailureMessage(
          e,
          fallback:
              'Attendance was not sent. Check your connection and try again.',
        );
      });
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<Position?> _attendancePosition(OperationsConfig config) async {
    _usingLocalTestPosition = false;
    if (kIsWeb) {
      try {
        // Some embedded browsers do not implement the Permissions API, so
        // checkPermission reports denied even though getCurrentPosition can
        // still show the browser prompt and return a valid position.
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Desktop browsers and embedded local test browsers may have no GPS
        // provider even after permission is granted. Keep production strict,
        // but allow the complete attendance workflow to be exercised from a
        // localhost build using the configured branch point.
        if (isLocalAttendanceHost(Uri.base.host)) {
          _usingLocalTestPosition = true;
          return Position(
            longitude: config.branchLongitude,
            latitude: config.branchLatitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
            isMocked: true,
          );
        }
        return null;
      }
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 12));
  }

  Future<String> _uploadAttendanceSelfie({
    required XFile image,
    required List<int> bytes,
    required String userId,
    required String dayKey,
  }) async {
    if (kIsWeb && isLocalAttendanceHost(Uri.base.host)) {
      final mimeType = image.mimeType?.startsWith('image/') == true
          ? image.mimeType!
          : 'image/jpeg';
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    }
    try {
      return await ref.read(storageRepositoryProvider).uploadXFile(
            file: image,
            folder: 'attendance/$userId',
            fileName: '${dayKey}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
    } catch (error) {
      throw StateError(
        'Selfie upload was blocked. Deploy Storage rules and configure Storage CORS for web testing.',
      );
    }
  }

  String _selfieFailureMessage(
    Object error, {
    required String fallback,
  }) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('permission-denied') ||
        normalized.contains('unauthorized')) {
      return 'Selfie upload is not permitted for this account. Sign out, sign in, and try again.';
    }
    if (normalized.contains('object-not-found') ||
        normalized.contains('bucket-not-found')) {
      return 'Selfie storage is temporarily unavailable. Please try again shortly.';
    }
    if (normalized.contains('network') || normalized.contains('timeout')) {
      return 'Selfie upload could not connect. Check your internet and try again.';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(operationsConfigProvider);
    final attendanceAsync = ref.watch(technicianAttendanceProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final hasFaceReference =
        (user?.faceReferenceSignature ?? '').trim().isNotEmpty;
    final config = configAsync.valueOrNull;
    final now = DateTime.now();
    final windowText = config == null
        ? 'Attendance window loading'
        : 'Morning attendance closes at ${_formatAttendanceTime(config.endFor(now))}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: AppTheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Attendance required',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                    'Mark today once with Face ID and location. After this, jobs unlock and live location stays shared until sign out.',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$windowText. Uploads after this are marked late.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        // Web notice banner
        if (kIsWeb)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: Colors.amber.shade800, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Please upload a selfie photo. Uploads after the cutoff are marked late.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text("TODAY'S ATTENDANCE",
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Good Morning, ${user?.name.split(' ').first ?? 'Technician'}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!_attendanceStarted) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'What is your status today?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _startPresentFlow,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("I'm Present"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _confirmLeave,
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text("I'm on Leave"),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    _AttendanceStepIndicator(
                      number: 1,
                      label: 'Selfie',
                      complete: _attendanceStep > 1,
                      active: _attendanceStep == 1,
                    ),
                    const Expanded(child: Divider()),
                    _AttendanceStepIndicator(
                      number: 2,
                      label: 'Location',
                      complete: _attendanceStep > 2,
                      active: _attendanceStep == 2,
                    ),
                    const Expanded(child: Divider()),
                    _AttendanceStepIndicator(
                      number: 3,
                      label: 'Confirm',
                      complete: _marked,
                      active: _attendanceStep == 3,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_attendanceStep == 1) ...[
                  const Icon(Icons.camera_front_outlined,
                      size: 48, color: AppTheme.primary),
                  const SizedBox(height: 8),
                  const Text(
                    'Step 1 — Selfie Verification',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Take a selfie to verify your attendance',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 180,
                    width: 240,
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.face_retouching_natural, size: 70),
                        SizedBox(height: 8),
                        Text('Center your face inside the frame'),
                      ],
                    ),
                  ),
                ] else if (_attendanceStep == 2) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      _attendanceSelfieBytes!,
                      height: 180,
                      width: 240,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '✓ Selfie verified',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Step 2 — Location Verification',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const Text('📍 Current Location'),
                ] else ...[
                  const Icon(Icons.verified_outlined,
                      size: 48, color: Colors.green),
                  const SizedBox(height: 8),
                  const Text(
                    'Confirm Attendance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AttendanceConfirmationRow(
                    label: 'Selfie',
                    value: '✓ Verified',
                  ),
                  _AttendanceConfirmationRow(
                    label: 'Location',
                    value: '✓ Detected',
                  ),
                  _AttendanceConfirmationRow(
                    label: 'Date',
                    value: DateFormat('MMMM d, yyyy').format(now),
                  ),
                  _AttendanceConfirmationRow(
                    label: 'Attendance time',
                    value: 'Recorded when you confirm',
                  ),
                  _AttendanceConfirmationRow(
                    label: 'Curfew',
                    value: config == null
                        ? '9:45 AM'
                        : _formatAttendanceTime(config.endFor(now)),
                  ),
                  _AttendanceConfirmationRow(
                    label: 'Status',
                    value: config != null && now.isAfter(config.endFor(now))
                        ? 'Late (after ${_formatAttendanceTime(config.endFor(now))})'
                        : 'Present',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your attendance will now be recorded and your location tracking will begin.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Text(_result!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _enrolling || _loading ? null : _enrollFace,
                  icon: _enrolling
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(hasFaceReference
                          ? Icons.verified_user_outlined
                          : Icons.badge_outlined),
                  label: Text(_enrolling
                      ? 'Saving Face ID...'
                      : hasFaceReference
                          ? 'Update Face ID reference'
                          : 'Register Face ID reference'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _loading || _enrolling || !_attendanceStarted
                      ? null
                      : _attendanceStep == 1
                          ? _captureAttendanceSelfie
                          : _attendanceStep == 2
                              ? _verifyAttendanceLocation
                              : _confirmStagedAttendance,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_attendanceStep == 1
                          ? Icons.photo_camera
                          : _attendanceStep == 2
                              ? Icons.location_on
                              : Icons.verified),
                  label: Text(_loading
                      ? 'Please wait...'
                      : _attendanceStep == 1
                          ? "✓ I'm Present — Take Selfie"
                          : _attendanceStep == 2
                              ? 'Verify Location'
                              : 'Confirm Attendance'),
                ),
                if (_attendanceSelfie != null && !_marked) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _setViewState(() {
                              _attendanceStep = 1;
                              _attendanceSelfie = null;
                              _attendanceSelfieBytes = null;
                              _attendanceLocation = null;
                              _attendanceFaceMatch = null;
                              _result = null;
                            }),
                    icon: const Icon(Icons.refresh),
                    label: Text(_attendanceStep == 3
                        ? 'Cancel attendance'
                        : 'Retake selfie'),
                  ),
                ],
                if (_attendanceStarted && _attendanceStep == 1 && !_marked) ...[
                  const Divider(height: 28),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _confirmLeave,
                    icon: const Icon(Icons.close),
                    label: const Text("I'm on Leave"),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TechnicianAttendanceHistory(attendanceAsync: attendanceAsync),
      ],
    );
  }
}

class _AttendanceStepIndicator extends StatelessWidget {
  const _AttendanceStepIndicator({
    required this.number,
    required this.label,
    required this.complete,
    required this.active,
  });

  final int number;
  final String label;
  final bool complete;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = complete || active ? AppTheme.primary : AppTheme.divider;
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: complete
              ? const Icon(Icons.check, size: 18)
              : Text('$number',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active || complete
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary,
            )),
      ],
    );
  }
}

class _AttendanceConfirmationRow extends StatelessWidget {
  const _AttendanceConfirmationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text('$label:')),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TechnicianAttendanceHistory extends StatelessWidget {
  const _TechnicianAttendanceHistory({required this.attendanceAsync});

  final AsyncValue<List<Attendance>> attendanceAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My attendance',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            attendanceAsync.when(
              data: (records) {
                if (records.isEmpty) {
                  return const Text(
                    'No attendance records yet.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: [
                    for (final record in records.take(12))
                      _TechnicianAttendanceRow(record: record),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(),
              ),
              error: (error, stackTrace) => Text(
                'Attendance history could not be loaded. ${error.toString()}',
                style: const TextStyle(color: Color(0xFFD95C2A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnicianAttendanceRow extends StatelessWidget {
  const _TechnicianAttendanceRow({required this.record});

  final Attendance record;

  @override
  Widget build(BuildContext context) {
    final statusLabel = _attendanceStatusLabel(record.status);
    final statusColor = _attendanceStatusColor(record.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(
            record.status == 'present'
                ? Icons.verified_outlined
                : Icons.info_outline,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(record.timestamp),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  record.faceMatchPassed ? 'Face ID matched' : 'Face ID failed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _AttendanceStatusChip(
            label: statusLabel,
            color: statusColor,
          ),
        ],
      ),
    );
  }
}

String _attendanceStatusLabel(String status) {
  return switch (status) {
    'present' => 'Present',
    'late' => 'Late',
    'face_failed' => 'Face failed',
    'absent' => 'Absent',
    _ => status.isEmpty ? 'Not marked' : status,
  };
}

Color _attendanceStatusColor(String status) {
  return switch (status) {
    'present' => AppTheme.accent,
    'late' => const Color(0xFFF08C00),
    'face_failed' => const Color(0xFFD95C2A),
    'absent' => const Color(0xFFD95C2A),
    _ => AppTheme.textSecondary,
  };
}

class _AttendanceStatusChip extends StatelessWidget {
  const _AttendanceStatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MonthlyScheduleView extends ConsumerStatefulWidget {
  const _MonthlyScheduleView();

  @override
  ConsumerState<_MonthlyScheduleView> createState() =>
      _MonthlyScheduleViewState();
}

class _MonthlyScheduleViewState extends ConsumerState<_MonthlyScheduleView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final bookings =
        ref.watch(technicianBookingsProvider).valueOrNull ?? const <Booking>[];
    final monthBookings = bookings
        .where((booking) =>
            booking.preferredDate.year == _month.year &&
            booking.preferredDate.month == _month.month)
        .toList()
      ..sort((a, b) => a.preferredDate.compareTo(b.preferredDate));
    final byDay = <int, List<Booking>>{};
    for (final booking in monthBookings) {
      byDay.putIfAbsent(booking.preferredDate.day, () => []).add(booking);
    }
    final firstWeekday = DateTime(_month.year, _month.month).weekday;
    final dayCount = DateTime(_month.year, _month.month + 1, 0).day;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => setState(() =>
                          _month = DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat('MMMM yyyy').format(_month),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => setState(() =>
                          _month = DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final day in [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun'
                    ])
                      Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 54,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: firstWeekday - 1 + dayCount,
                  itemBuilder: (context, index) {
                    if (index < firstWeekday - 1) return const SizedBox();
                    final day = index - firstWeekday + 2;
                    final count = byDay[day]?.length ?? 0;
                    final isToday = _sameCalendarDay(
                      DateTime(_month.year, _month.month, day),
                      DateTime.now(),
                    );
                    return Container(
                      decoration: BoxDecoration(
                        color: count > 0
                            ? AppTheme.primary.withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isToday ? AppTheme.primary : AppTheme.divider,
                          width: isToday ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$day',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          if (count > 0)
                            Text(
                              '$count job${count == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${monthBookings.length} scheduled job${monthBookings.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (monthBookings.isEmpty)
          const _EmptyJobsCard(
            title: 'No jobs this month',
            message: 'Assigned visits will appear in this monthly schedule.',
          )
        else
          for (final booking in monthBookings)
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.event_available, color: AppTheme.primary),
                title: Text(
                  '${DateFormat('dd MMM').format(booking.preferredDate)} · ${booking.preferredTime}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${booking.applianceType} · ${booking.customerName}\n${booking.address}',
                ),
                isThreeLine: true,
              ),
            ),
      ],
    );
  }
}

class _TechnicianReviewsView extends ConsumerWidget {
  const _TechnicianReviewsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final reviewsAsync = ref.watch(currentTechnicianReviewsProvider);
    return reviewsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Reviews could not be loaded. Please try again.'),
      ),
      data: (reviews) {
        final average = reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (sum, item) => sum + item.rating) /
                reviews.length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: AppTheme.primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      user?.technicianCategory.label ?? 'Junior',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reviews.isEmpty
                          ? 'No rating yet'
                          : average.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    _ReviewStars(rating: average),
                    const SizedBox(height: 6),
                    Text(
                      '${reviews.length} consolidated review${reviews.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              const _EmptyJobsCard(
                title: 'No reviews yet',
                message: 'Customer and admin feedback will appear here.',
              )
            else
              for (final review in reviews)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppTheme.starColor.withValues(alpha: 0.15),
                      child: Text('${review.rating}★'),
                    ),
                    title: Text(
                      review.reviewerName.trim().isNotEmpty
                          ? review.reviewerName
                          : review.reviewerRole == 'customer'
                              ? 'Customer'
                              : 'Admin',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${review.text}\n${DateFormat('dd MMM yyyy').format(review.createdAt)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ReviewStars extends StatelessWidget {
  const _ReviewStars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 1; index <= 5; index++)
          Icon(
            index <= rating.round() ? Icons.star : Icons.star_border,
            color: AppTheme.starColor,
          ),
      ],
    );
  }
}

class _EarningsView extends ConsumerWidget {
  const _EarningsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills =
        ref.watch(technicianBillsProvider).valueOrNull ?? const <Bill>[];
    final technician = ref.watch(currentUserProvider).valueOrNull;
    final technicianId = technician?.uid ?? '';
    final monthlySalary = technician?.monthlySalary ?? 0;
    final customIncentives = technicianId.isEmpty
        ? const <TechnicianIncentive>[]
        : ref.watch(technicianIncentivesProvider(technicianId)).valueOrNull ??
            const <TechnicianIncentive>[];
    final range = ref.watch(_earningsRangeProvider);
    final now = DateTime.now();
    final employmentStart = technician?.approvedAt ?? technician?.createdAt;
    final paidBills = bills.where((bill) => bill.isPaid).toList();
    final daily = _sumBillsForDay(paidBills, now);
    final monthly = paidBills
        .where((bill) =>
            bill.revenueDate.year == now.year &&
            bill.revenueDate.month == now.month)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final lifetimeCollection = paidBills
        .where((bill) =>
            employmentStart == null ||
            !bill.revenueDate.isBefore(employmentStart))
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final monthDates = _datesForRange(_EarningsRange.month, now);
    final targetIncentive = monthDates.fold<double>(
      0,
      (sum, date) =>
          sum + automaticDailyIncentive(_sumBillsForDay(paidBills, date)),
    );
    final adminIncentive = customIncentives
        .where((item) =>
            item.awardedAt.year == now.year &&
            item.awardedAt.month == now.month)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final monthlyIncentive = targetIncentive + adminIncentive;
    final totalMonthlyEarnings = monthlySalary + monthlyIncentive;
    final chartPoints = _earningPointsForRange(
      range: range,
      now: now,
      paidBills: paidBills,
      monthlySalary: monthlySalary,
    );
    final rangeCollection =
        chartPoints.fold<double>(0, (sum, point) => sum + point.collection);
    final rangeIncentive =
        chartPoints.fold<double>(0, (sum, point) => sum + point.incentive);
    final rangeSalary =
        chartPoints.fold<double>(0, (sum, point) => sum + point.salary);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Today collection',
              value: 'Rs. ${daily.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Lifetime confirmed collection',
              value: 'Rs. ${lifetimeCollection.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Monthly base salary',
              value: 'Rs. ${monthlySalary.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Automatic incentive',
              value: 'Rs. ${targetIncentive.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Admin-added incentive',
              value: 'Rs. ${adminIncentive.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Total earnings',
              value: 'Rs. ${totalMonthlyEarnings.toStringAsFixed(0)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Earnings growth',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    SegmentedButton<_EarningsRange>(
                      segments: [
                        for (final item in _EarningsRange.values)
                          ButtonSegment(
                            value: item,
                            label: Text(item.label),
                          ),
                      ],
                      selected: {range},
                      onSelectionChanged: (value) {
                        ref.read(_earningsRangeProvider.notifier).state =
                            value.first;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Collection + prorated salary + daily incentive for ${range.label.toLowerCase()} view',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _EarningsLineChartPainter(points: chartPoints),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MiniEarningChip(
                      label: '${range.label} collection',
                      value: 'Rs. ${rangeCollection.toStringAsFixed(0)}',
                    ),
                    _MiniEarningChip(
                      label: '${range.label} automatic incentive',
                      value: 'Rs. ${rangeIncentive.toStringAsFixed(0)}',
                    ),
                    _MiniEarningChip(
                      label: '${range.label} salary',
                      value: 'Rs. ${rangeSalary.toStringAsFixed(0)}',
                    ),
                    _MiniEarningChip(
                      label: 'Total',
                      value:
                          'Rs. ${(rangeCollection + rangeIncentive + rangeSalary).toStringAsFixed(0)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payout summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _PayoutRow(
                  label: 'Paid this month',
                  value: 'Rs. ${monthly.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Monthly base salary',
                  value: 'Rs. ${monthlySalary.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Automatic ₹8,000-rule incentive',
                  value: 'Rs. ${targetIncentive.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Additional incentive added by admin',
                  value: 'Rs. ${adminIncentive.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Total incentive this month',
                  value: 'Rs. ${monthlyIncentive.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Total earnings this month',
                  value: 'Rs. ${totalMonthlyEarnings.toStringAsFixed(0)}',
                ),
                const Divider(height: 24),
                _PayoutRow(
                  label: employmentStart == null
                      ? 'Career confirmed collection'
                      : 'Career collection since ${DateFormat('dd MMM yyyy').format(employmentStart)}',
                  value: 'Rs. ${lifetimeCollection.toStringAsFixed(0)}',
                ),
                _PayoutRow(label: 'Recorded bills', value: '${bills.length}'),
                const SizedBox(height: 8),
                const Text(
                  'Incentive starts at Rs. 8,000 collection and increases with higher daily collection.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                if (customIncentives.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Recent admin incentives',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  for (final incentive in customIncentives.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.card_giftcard,
                          color: AppTheme.accent),
                      title: Text(incentive.description),
                      subtitle: Text(DateFormat('dd MMM yyyy')
                          .format(incentive.awardedAt)),
                      trailing: Text(
                        'Rs. ${incentive.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EarningPoint {
  const _EarningPoint({
    required this.date,
    required this.collection,
    required this.incentive,
    required this.salary,
  });

  final DateTime date;
  final double collection;
  final double incentive;
  final double salary;

  double get total => collection + incentive + salary;
}

List<DateTime> _datesForRange(_EarningsRange range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    _EarningsRange.week => List.generate(
        7,
        (index) => today.subtract(Duration(days: 6 - index)),
      ),
    _EarningsRange.month => List.generate(
        today.day,
        (index) => DateTime(today.year, today.month, index + 1),
      ),
  };
}

List<_EarningPoint> _earningPointsForRange({
  required _EarningsRange range,
  required DateTime now,
  required List<Bill> paidBills,
  required double monthlySalary,
}) {
  return _datesForRange(range, now).map((date) {
    final collection = _sumBillsForDay(paidBills, date);
    return _EarningPoint(
      date: date,
      collection: collection,
      incentive: automaticDailyIncentive(collection),
      salary: proratedDailySalary(monthlySalary, date),
    );
  }).toList();
}

double _sumBillsForDay(List<Bill> bills, DateTime date) {
  return bills
      .where((bill) =>
          bill.revenueDate.year == date.year &&
          bill.revenueDate.month == date.month &&
          bill.revenueDate.day == date.day)
      .fold<double>(0, (sum, bill) => sum + bill.amount);
}

class _EarningsLineChartPainter extends CustomPainter {
  const _EarningsLineChartPainter({required this.points});

  final List<_EarningPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = AppTheme.divider
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = AppTheme.divider.withValues(alpha: .55)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()..color = AppTheme.accent;
    const left = 46.0;
    const right = 12.0;
    const top = 14.0;
    const bottom = 34.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.topLeft, chart.bottomLeft, axisPaint);

    final maxValue = points.fold<double>(
      0,
      (max, point) => point.total > max ? point.total : max,
    );
    final scaleMax = maxValue <= 0 ? 1000.0 : maxValue * 1.15;
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * (i / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _paintText(
        canvas,
        'Rs.${(scaleMax * i / 3).round()}',
        Offset(0, y - 8),
        const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
      );
    }

    if (points.isEmpty) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * i / (points.length - 1));
      final y = chart.bottom - (points[i].total / scaleMax) * chart.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * i / (points.length - 1));
      final y = chart.bottom - (points[i].total / scaleMax) * chart.height;
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    final labelIndexes = points.length <= 7
        ? List.generate(points.length, (index) => index)
        : [0, (points.length / 2).floor(), points.length - 1];
    for (final index in labelIndexes) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + (chart.width * index / (points.length - 1));
      _paintText(
        canvas,
        DateFormat('d MMM').format(points[index].date),
        Offset(x - 18, chart.bottom + 10),
        const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    final span = TextSpan(text: text, style: style);
    final painter = TextPainter(
      text: span,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _EarningsLineChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _MiniEarningChip extends StatelessWidget {
  const _MiniEarningChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon,
      required this.text,
      this.actionLabel,
      this.onAction});

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.width = 180,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmptyJobsCard extends StatelessWidget {
  const _EmptyJobsCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAttendanceTime(DateTime time) {
  return DateFormat('hh:mm a').format(time);
}

String _formatBillAmount(Bill bill) {
  return 'Rs. ${bill.amount.toStringAsFixed(0)}';
}

IconData _applianceIcon(String appliance) {
  return switch (appliance.toLowerCase()) {
    String s when s.contains('ac') || s.contains('conditioner') =>
      Icons.ac_unit,
    String s when s.contains('fridge') || s.contains('refrigerator') =>
      Icons.kitchen,
    String s when s.contains('washer') || s.contains('washing') =>
      Icons.local_laundry_service,
    String s when s.contains('tv') => Icons.tv,
    String s when s.contains('water') => Icons.water_drop,
    _ => Icons.home_repair_service,
  };
}
