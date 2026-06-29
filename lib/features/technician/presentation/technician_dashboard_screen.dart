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
import '../../../core/enums/booking_status.dart';
import '../../../core/services/location_tracking_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../estimates/data/estimate_repository.dart';
import '../../estimates/domain/estimate.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/data/storage_repository.dart';
import '../../shared/domain/bill.dart';
import '../data/technician_repository.dart';
import '../domain/attendance.dart';
import '../domain/technician_location.dart';

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

final technicianEstimateProvider =
    StreamProvider.autoDispose.family<Estimate?, String>((ref, bookingId) {
  return ref.watch(estimateRepositoryProvider).watchForBooking(bookingId);
});

final _technicianTabProvider = StateProvider.autoDispose<int>((ref) => 0);
final _earningsRangeProvider =
    StateProvider.autoDispose<_EarningsRange>((ref) => _EarningsRange.week);

enum _EarningsRange {
  week('Week'),
  month('Month');

  const _EarningsRange(this.label);
  final String label;
}

class TechnicianDashboardScreen extends ConsumerWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_technicianTabProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('FixNow Technician App'),
        actions: [
          IconButton(
            tooltip: 'Share live location',
            onPressed: () => _shareLocation(context, ref, null),
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: tab,
          children: const [
            _JobsView(),
            _AttendanceView(),
            _EarningsView(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) =>
            ref.read(_technicianTabProvider.notifier).state = index,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.work_outline),
              selectedIcon: Icon(Icons.work),
              label: 'Jobs'),
          NavigationDestination(
              icon: Icon(Icons.how_to_reg_outlined),
              selectedIcon: Icon(Icons.how_to_reg),
              label: 'Attendance'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Earnings'),
        ],
      ),
    );
  }

  static Future<Position?> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  static Future<void> _shareLocation(
      BuildContext context, WidgetRef ref, String? bookingId) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final position = await _position();
    if (user == null || position == null) return;
    await ref.read(technicianRepositoryProvider).updateLocation(
          TechnicianLocation(
            technicianId: user.uid,
            latitude: position.latitude,
            longitude: position.longitude,
            updatedAt: DateTime.now(),
            activeBookingId: bookingId,
          ),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live location shared with the customer')),
      );
    }
  }
}

class _JobsView extends ConsumerWidget {
  const _JobsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(technicianBookingsProvider);
    return bookings.when(
      data: (items) {
        final active =
            items.where((b) => b.status != BookingStatus.closed).toList();
        final done = items.length - active.length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroPanel(active: active.length, done: done),
            const SizedBox(height: 18),
            Text('Assigned jobs',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (active.isEmpty) const _EmptyJobsCard(),
            ...active.map((booking) => _TechnicianJobCard(booking: booking)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.active, required this.done});

  final int active;
  final int done;

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
          const Text('Today route',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          const Text('Accept, travel, estimate, repair',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
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

class _TechnicianJobCard extends ConsumerWidget {
  const _TechnicianJobCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookingRepositoryProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final estimate =
        ref.watch(technicianEstimateProvider(booking.id)).valueOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(_applianceIcon(booking.applianceType),
                      color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.applianceType,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(booking.customerName,
                          style:
                              const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 3),
                      Text(booking.problemDescription,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Chip(label: Text(booking.status.label)),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRail(status: booking.status),
            const SizedBox(height: 12),
            _InfoRow(
                icon: Icons.place_outlined,
                text: booking.address,
                actionLabel: 'Map',
                onAction: () => _openMaps(context, booking)),
            _InfoRow(
                icon: Icons.phone_outlined,
                text: booking.phone,
                actionLabel: 'WhatsApp',
                onAction: () => _openWhatsApp(context, booking)),
            _InfoRow(
                icon: Icons.schedule,
                text: 'Preferred time: ${booking.preferredTime}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (booking.status == BookingStatus.technicianAssigned) ...[
                  FilledButton.tonalIcon(
                    onPressed: user == null
                        ? null
                        : () => repo.transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.technicianAssigned,
                              next: BookingStatus.accepted,
                            ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Accept'),
                  ),
                  OutlinedButton.icon(
                    onPressed: user == null
                        ? null
                        : () => repo.rejectAssignment(
                              bookingId: booking.id,
                              technicianId: user.uid,
                            ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ],
                if (booking.status == BookingStatus.accepted)
                  FilledButton.icon(
                    onPressed: () async {
                      if (user == null) return;
                      await repo.transitionStatus(
                        bookingId: booking.id,
                        technicianId: user.uid,
                        expected: BookingStatus.accepted,
                        next: BookingStatus.onTheWay,
                      );
                      await ref.read(locationTrackingServiceProvider).start(
                            technicianId: user.uid,
                            bookingId: booking.id,
                          );
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start journey'),
                  ),
                if (booking.status == BookingStatus.onTheWay)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () async {
                            await repo.transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.onTheWay,
                              next: BookingStatus.arrived,
                            );
                            await ref
                                .read(locationTrackingServiceProvider)
                                .stop();
                            await ref
                                .read(technicianRepositoryProvider)
                                .stopSharingLocation(user.uid);
                          },
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Arrived'),
                  ),
                if (booking.status == BookingStatus.arrived)
                  FilledButton.icon(
                    onPressed: () => _showEstimateDialog(context, ref),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Create estimate'),
                  ),
                if (booking.status == BookingStatus.estimateSent)
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context, booking),
                    icon: const Icon(Icons.hourglass_top),
                    label: const Text('Awaiting approval'),
                  ),
                if (booking.status == BookingStatus.estimateApproved)
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () => repo.transitionStatus(
                              bookingId: booking.id,
                              technicianId: user.uid,
                              expected: BookingStatus.estimateApproved,
                              next: BookingStatus.serviceStarted,
                            ),
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('Start work'),
                  ),
                if (booking.status == BookingStatus.serviceStarted)
                  FilledButton.icon(
                    onPressed: () async {
                      if (user == null) return;
                      await repo.transitionStatus(
                        bookingId: booking.id,
                        technicianId: user.uid,
                        expected: BookingStatus.serviceStarted,
                        next: BookingStatus.serviceCompleted,
                      );
                    },
                    icon: const Icon(Icons.done_all),
                    label: const Text('Complete'),
                  ),
                if (booking.status == BookingStatus.serviceCompleted)
                  FilledButton.icon(
                    onPressed: user == null || estimate == null
                        ? null
                        : () => ref.read(billRepositoryProvider).generateBill(
                              bookingId: booking.id,
                              customerId: booking.customerId,
                              technicianId: user.uid,
                              amount: estimate.total,
                            ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Generate bill'),
                  ),
                OutlinedButton.icon(
                    onPressed: booking.status == BookingStatus.arrived
                        ? () => _uploadServicePhoto(context, ref, 'before')
                        : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Before')),
                OutlinedButton.icon(
                    onPressed: booking.status == BookingStatus.serviceStarted
                        ? () => _uploadServicePhoto(context, ref, 'during')
                        : null,
                    icon: const Icon(Icons.camera_outlined),
                    label: const Text('During')),
                OutlinedButton.icon(
                    onPressed: booking.status == BookingStatus.serviceStarted
                        ? () => _uploadServicePhoto(context, ref, 'after')
                        : null,
                    icon: const Icon(Icons.camera_enhance_outlined),
                    label: const Text('After')),
                TextButton.icon(
                    onPressed: () => context.push('/booking/${booking.id}'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Details')),
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _openMaps(BuildContext context, Booking booking) async {
    final query = booking.latitude != null && booking.longitude != null
        ? '${booking.latitude},${booking.longitude}'
        : Uri.encodeComponent(booking.address);
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open Google Maps')));
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

class _AttendanceViewState extends ConsumerState<_AttendanceView> {
  bool _loading = false;
  bool _marked = false;
  String? _result;

  Future<void> _markAttendance() async {
    setState(() {
      _loading = true;
      _result = 'Opening selfie picker...';
    });
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) {
        setState(() => _result = 'Not signed in.');
        return;
      }

      final image = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 45,
        maxWidth: 640,
        maxHeight: 640,
      );

      if (image == null) {
        setState(() => _result = 'No photo selected. Please try again.');
        return;
      }

      setState(() => _result = 'Saving marked time and selfie...');
      final bytes = await image.readAsBytes().timeout(
            const Duration(seconds: 12),
          );
      if (bytes.length > 650 * 1024) {
        setState(() {
          _result =
              'Selfie image is too large. Please choose a smaller selfie photo.';
        });
        return;
      }
      final contentType = image.mimeType ?? 'image/jpeg';
      final selfieDataUrl = 'data:$contentType;base64,${base64Encode(bytes)}';
      await ref.read(technicianRepositoryProvider).markAttendance(
            Attendance(
              id: '',
              technicianId: user.uid,
              selfieUrl: selfieDataUrl,
              latitude: 0,
              longitude: 0,
              timestamp: DateTime.now(),
              faceMatchPassed: false,
              geofencePassed: false,
            ),
          );

      setState(() {
        _marked = true;
        _result = 'Attendance sent to admin for review.';
      });
    } catch (e) {
      setState(() {
        _marked = false;
        _result =
            'Attendance was not sent. Please check your connection and try again. ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Technician attendance',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              SizedBox(height: 6),
              Text('Selfie attendance sent to admin review',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                    'Please upload a selfie photo. Your marked time and image will be sent to admin for review.',
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
                Icon(_marked ? Icons.verified : Icons.face_retouching_natural,
                    size: 54,
                    color: _marked ? AppTheme.accent : AppTheme.primary),
                const SizedBox(height: 10),
                Text(_marked ? 'Attendance marked' : 'Mark attendance',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    _result ??
                        'Mark attendance with a selfie. Admin will verify it.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loading ? null : _markAttendance,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(kIsWeb ? Icons.upload_file : Icons.photo_camera),
                  label: Text(_loading
                      ? 'Submitting...'
                      : kIsWeb
                          ? 'Upload selfie photo'
                          : 'Take selfie'),
                ),
              ],
            ),
          ),
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
    final range = ref.watch(_earningsRangeProvider);
    final now = DateTime.now();
    final paidBills = bills.where((bill) => bill.isPaid).toList();
    final daily = _sumBillsForDay(paidBills, now);
    final monthly = paidBills
        .where((bill) =>
            bill.createdAt.year == now.year &&
            bill.createdAt.month == now.month)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final pending = bills
        .where((bill) => !bill.isPaid)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final monthDates = _datesForRange(_EarningsRange.month, now);
    final monthlyIncentive = monthDates.fold<double>(
      0,
      (sum, date) => sum + _dailyIncentive(_sumBillsForDay(paidBills, date)),
    );
    final chartPoints = _earningPointsForRange(
      range: range,
      now: now,
      paidBills: paidBills,
    );
    final rangeCollection =
        chartPoints.fold<double>(0, (sum, point) => sum + point.collection);
    final rangeIncentive =
        chartPoints.fold<double>(0, (sum, point) => sum + point.incentive);

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
              label: 'Monthly payout',
              value: 'Rs. ${monthly.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Incentives',
              value: 'Rs. ${monthlyIncentive.toStringAsFixed(0)}',
            ),
            _MetricCard(
              label: 'Pending release',
              value: 'Rs. ${pending.toStringAsFixed(0)}',
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
                  'Collection + daily incentive for ${range.label.toLowerCase()} view',
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
                      label: '${range.label} incentive',
                      value: 'Rs. ${rangeIncentive.toStringAsFixed(0)}',
                    ),
                    _MiniEarningChip(
                      label: 'Total',
                      value:
                          'Rs. ${(rangeCollection + rangeIncentive).toStringAsFixed(0)}',
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
                  label: 'Incentive this month',
                  value: 'Rs. ${monthlyIncentive.toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Total earnings this month',
                  value:
                      'Rs. ${(monthly + monthlyIncentive).toStringAsFixed(0)}',
                ),
                _PayoutRow(
                  label: 'Pending release',
                  value: 'Rs. ${pending.toStringAsFixed(0)}',
                ),
                const Divider(height: 24),
                _PayoutRow(label: 'Recorded bills', value: '${bills.length}'),
                const SizedBox(height: 8),
                const Text(
                  'Incentive starts at Rs. 8,000 collection and increases with higher daily collection.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
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
  });

  final DateTime date;
  final double collection;
  final double incentive;

  double get total => collection + incentive;
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
}) {
  return _datesForRange(range, now).map((date) {
    final collection = _sumBillsForDay(paidBills, date);
    return _EarningPoint(
      date: date,
      collection: collection,
      incentive: _dailyIncentive(collection),
    );
  }).toList();
}

double _sumBillsForDay(List<Bill> bills, DateTime date) {
  return bills
      .where((bill) =>
          bill.createdAt.year == date.year &&
          bill.createdAt.month == date.month &&
          bill.createdAt.day == date.day)
      .fold<double>(0, (sum, bill) => sum + bill.amount);
}

double _dailyIncentive(double collection) {
  if (collection >= 20000) {
    return 1000 + ((collection - 20000) / 1000).floor() * 100;
  }
  if (collection >= 17500) return 750;
  if (collection >= 15000) return 500;
  if (collection >= 12500) return 400;
  if (collection >= 10000) return 300;
  if (collection >= 9000) return 200;
  if (collection >= 8000) return 100;
  return 0;
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

class _StatusRail extends StatelessWidget {
  const _StatusRail({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    const steps = [
      BookingStatus.technicianAssigned,
      BookingStatus.accepted,
      BookingStatus.onTheWay,
      BookingStatus.arrived,
      BookingStatus.estimateSent,
      BookingStatus.estimateApproved,
      BookingStatus.serviceStarted,
      BookingStatus.serviceCompleted,
    ];
    final index = steps.indexOf(status);
    return Row(
      children: List.generate(steps.length, (i) {
        final passed = index >= i;
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 4),
            decoration: BoxDecoration(
                color: passed ? AppTheme.accent : AppTheme.divider,
                borderRadius: BorderRadius.circular(20)),
          ),
        );
      }),
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
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
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
  const _EmptyJobsCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.accent),
            SizedBox(width: 10),
            Expanded(
                child: Text(
                    'No active assignments. New admin-assigned jobs will appear here.')),
          ],
        ),
      ),
    );
  }
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
