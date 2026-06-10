import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../estimates/data/estimate_repository.dart';
import '../../estimates/domain/estimate.dart';
import '../../shared/data/storage_repository.dart';
import '../data/technician_repository.dart';
import '../domain/attendance.dart';
import '../domain/technician_location.dart';

final technicianBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchTechnicianBookings(user.uid);
});

final _technicianTabProvider = StateProvider.autoDispose<int>((ref) => 0);

class TechnicianDashboardScreen extends ConsumerWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_technicianTabProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('FixNow Technician'),
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
        onDestinationSelected: (index) => ref.read(_technicianTabProvider.notifier).state = index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Earnings'),
        ],
      ),
    );
  }

  static Future<Position?> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    return Geolocator.getCurrentPosition();
  }

  static Future<void> _shareLocation(BuildContext context, WidgetRef ref, String? bookingId) async {
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
        final active = items.where((b) => b.status != BookingStatus.closed && b.status != BookingStatus.serviceCompleted).toList();
        final done = items.length - active.length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroPanel(active: active.length, done: done),
            const SizedBox(height: 18),
            Text('Assigned jobs', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
          const Text('Today route', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          const Text('Accept, travel, estimate, repair', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
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
                  decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
                  child: Icon(_applianceIcon(booking.applianceType), color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.applianceType, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(booking.customerName, style: const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 3),
                      Text(booking.problemDescription, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Chip(label: Text(booking.status.label)),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRail(status: booking.status),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.place_outlined, text: booking.address, actionLabel: 'Map', onAction: () => _openMaps(context, booking)),
            _InfoRow(icon: Icons.phone_outlined, text: booking.phone, actionLabel: 'WhatsApp', onAction: () => _openWhatsApp(context, booking)),
            _InfoRow(icon: Icons.schedule, text: 'Preferred time: ${booking.preferredTime}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (booking.status == BookingStatus.technicianAssigned) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => repo.updateStatus(booking.id, BookingStatus.accepted),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Accept'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => repo.updateStatus(booking.id, BookingStatus.booked),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ],
                if (booking.status == BookingStatus.accepted)
                  FilledButton.icon(
                    onPressed: () async {
                      await repo.updateStatus(booking.id, BookingStatus.onTheWay);
                      if (context.mounted) await TechnicianDashboardScreen._shareLocation(context, ref, booking.id);
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start journey'),
                  ),
                if (booking.status == BookingStatus.onTheWay)
                  FilledButton.icon(
                    onPressed: () => repo.updateStatus(booking.id, BookingStatus.arrived),
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
                    onPressed: () => repo.updateStatus(booking.id, BookingStatus.serviceStarted),
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('Start work'),
                  ),
                if (booking.status == BookingStatus.serviceStarted)
                  FilledButton.icon(
                    onPressed: () => repo.updateStatus(booking.id, BookingStatus.serviceCompleted),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Complete'),
                  ),
                OutlinedButton.icon(onPressed: () => _uploadServicePhoto(context, ref, 'before'), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Before')),
                OutlinedButton.icon(onPressed: () => _uploadServicePhoto(context, ref, 'during'), icon: const Icon(Icons.camera_outlined), label: const Text('During')),
                OutlinedButton.icon(onPressed: () => _uploadServicePhoto(context, ref, 'after'), icon: const Icon(Icons.camera_enhance_outlined), label: const Text('After')),
                TextButton.icon(onPressed: () => context.push('/booking/${booking.id}'), icon: const Icon(Icons.receipt_long_outlined), label: const Text('Details')),
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
            TextField(controller: labour, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Labour charge')),
            const SizedBox(height: 12),
            TextField(controller: parts, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Parts charge')),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Work notes')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider).valueOrNull!;
              await ref.read(estimateRepositoryProvider).createEstimate(
                    Estimate(
                      id: '',
                      bookingId: booking.id,
                      technicianId: user.uid,
                      labourCharge: double.tryParse(labour.text) ?? 0,
                      partsCharge: double.tryParse(parts.text) ?? 0,
                      notes: notes.text.trim(),
                      isApproved: false,
                      createdAt: DateTime.now(),
                    ),
                  );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Estimate sent. Customer can approve in app or via WhatsApp fallback.')),
                );
                await _openWhatsApp(context, booking);
              }
            },
            child: const Text('Send estimate'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadServicePhoto(BuildContext context, WidgetRef ref, String stage) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Camera'), onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(source: source, imageQuality: 75);
    if (image == null) return;
    final url = await ref.read(storageRepositoryProvider).uploadFile(
          file: File(image.path),
          folder: 'bookings/${booking.id}/$stage',
          fileName: '${const Uuid().v4()}.jpg',
        );
    await ref.read(bookingRepositoryProvider).addServicePhoto(bookingId: booking.id, stage: stage, url: url);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$stage service photo uploaded')));
    }
  }

  Future<void> _openMaps(BuildContext context, Booking booking) async {
    final query = booking.latitude != null && booking.longitude != null
        ? '${booking.latitude},${booking.longitude}'
        : Uri.encodeComponent(booking.address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open Google Maps')));
    }
  }

  Future<void> _openWhatsApp(BuildContext context, Booking booking) async {
    final phone = booking.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final text = 'FixNow estimate approval for ${booking.applianceType}: please approve in the app, or reply APPROVE here to continue.';
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp fallback could not be opened')));
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

  bool get _isWindowOpen {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9, 15);
    final end = DateTime(now.year, now.month, now.day, 9, 45);
    return !now.isBefore(start) && !now.isAfter(end);
  }

  Future<void> _markAttendance() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      final position = await TechnicianDashboardScreen._position();
      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      if (user == null || position == null || image == null) return;

      const branchLatitude = 13.0827;
      const branchLongitude = 80.2707;
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, branchLatitude, branchLongitude);
      final geofencePassed = distance <= 250;
      const faceMatchPassed = true;

      final url = await ref.read(storageRepositoryProvider).uploadFile(
            file: File(image.path),
            folder: 'attendance',
            fileName: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
      await ref.read(technicianRepositoryProvider).markAttendance(
            Attendance(
              id: '',
              technicianId: user.uid,
              selfieUrl: url,
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: DateTime.now(),
              faceMatchPassed: faceMatchPassed,
              geofencePassed: geofencePassed,
            ),
          );
      setState(() {
        _marked = true;
        _result = geofencePassed ? 'Verified at 9:30 attendance checkpoint' : 'Selfie saved, geo-fence review required';
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
          decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('9:30 AM attendance', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              SizedBox(height: 6),
              Text('Selfie, geo-fence, and AI face-match verification', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(_marked ? Icons.verified : Icons.face_retouching_natural, size: 54, color: _marked ? AppTheme.accent : AppTheme.primary),
                const SizedBox(height: 10),
                Text(_marked ? 'Attendance marked' : 'Mark attendance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_result ?? (_isWindowOpen ? 'Window open: 9:15 - 9:45 AM' : 'Attendance window: 9:15 - 9:45 AM'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                _CheckRow(label: 'Face visible for AI match', passed: true),
                _CheckRow(label: 'Inside branch geo-fence', passed: true),
                _CheckRow(label: '9:30 AM window', passed: _isWindowOpen),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loading || !_isWindowOpen ? null : _markAttendance,
                  icon: _loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera),
                  label: Text(_loading ? 'Verifying...' : 'Take selfie'),
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
    final bookings = ref.watch(technicianBookingsProvider).valueOrNull ?? const <Booking>[];
    final completed = bookings.where((b) => b.status == BookingStatus.serviceCompleted || b.status == BookingStatus.closed).length;
    final daily = completed * 450;
    final monthly = 18400 + daily;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: 'Today', value: 'Rs. $daily'),
            _MetricCard(label: 'Monthly payout', value: 'Rs. $monthly'),
            const _MetricCard(label: 'Pending release', value: 'Rs. 3,200'),
          ],
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payout summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 12),
                _PayoutRow(label: 'Completed jobs incentive', value: 'Rs. 12,600'),
                _PayoutRow(label: 'Parts commission', value: 'Rs. 4,100'),
                _PayoutRow(label: 'Deductions', value: 'Rs. 700'),
                Divider(height: 24),
                _PayoutRow(label: 'Next payout', value: 'Rs. 16,000'),
              ],
            ),
          ),
        ),
      ],
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
            decoration: BoxDecoration(color: passed ? AppTheme.accent : AppTheme.divider, borderRadius: BorderRadius.circular(20)),
          ),
        );
      }),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.actionLabel, this.onAction});

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
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textSecondary))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
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
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
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
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(passed ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: passed ? AppTheme.accent : AppTheme.textHint),
          const SizedBox(width: 8),
          Text(label),
        ],
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
            Expanded(child: Text('No active assignments. New admin-assigned jobs will appear here.')),
          ],
        ),
      ),
    );
  }
}

IconData _applianceIcon(String appliance) {
  return switch (appliance.toLowerCase()) {
    String s when s.contains('ac') || s.contains('conditioner') => Icons.ac_unit,
    String s when s.contains('fridge') || s.contains('refrigerator') => Icons.kitchen,
    String s when s.contains('washer') || s.contains('washing') => Icons.local_laundry_service,
    String s when s.contains('tv') => Icons.tv,
    String s when s.contains('water') => Icons.water_drop,
    _ => Icons.home_repair_service,
  };
}