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
import '../../../core/maps/google_static_map.dart';
import '../../../core/maps/route_recalculation.dart';
import '../../../core/services/face_match_service.dart';
import '../../../core/services/location_tracking_service.dart';
import '../../../core/services/reverse_geocoding_service.dart';
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
            branchId: user.branchId,
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
    final bills = ref.watch(technicianBillsProvider).valueOrNull ?? const [];
    final overtime =
        ref.watch(technicianOvertimeProvider).valueOrNull ?? const [];
    return bookings.when(
      data: (items) {
        final active =
            items.where((b) => isTechnicianBusyStatus(b.status)).toList();
        final held =
            items.where((b) => b.status == BookingStatus.onHold).toList();
        final billing = items
            .where((b) =>
                b.status == BookingStatus.serviceCompleted ||
                b.status == BookingStatus.billGenerated)
            .toList();
        final done = billing.length;
        return DefaultTabController(
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
                child: _HeroPanel(active: active.length, done: done),
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
                          'Completed jobs and final bill collection will appear here.',
                    ),
                    _JobTabList(
                      bookings: held,
                      emptyTitle: 'No jobs on hold',
                      emptyMessage: 'Jobs paused by admin will appear here.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
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
    BookingRepository bookingRepository() =>
        ref.read(bookingRepositoryProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
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
    final canMarkArrived = trackingThisBooking &&
        customerDistanceMeters != null &&
        customerDistanceMeters <= 150;
    final arrivalGateLabel = !trackingThisBooking
        ? 'Resume tracking first'
        : customerDistanceMeters == null
            ? 'Waiting for GPS'
            : '${_formatRouteDistance(customerDistanceMeters)} away';
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
                actionLabel: 'Directions',
                onAction: () => _openDirections(context, booking)),
            _InfoRow(
                icon: Icons.phone_outlined,
                text: booking.phone,
                actionLabel: 'WhatsApp',
                onAction: () => _openWhatsApp(context, booking)),
            _InfoRow(
                icon: Icons.schedule,
                text: 'Preferred time: ${booking.preferredTime}'),
            const SizedBox(height: 12),
            _TechnicianJobMap(
              booking: booking,
              technicianLocation: technicianLocation,
              onDirections: () => _openDirections(context, booking),
            ),
            const SizedBox(height: 12),
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
                    onPressed: () async {
                      if (user == null) return;
                      await bookingRepository().transitionStatus(
                        bookingId: booking.id,
                        technicianId: user.uid,
                        expected: BookingStatus.accepted,
                        next: BookingStatus.onTheWay,
                      );
                      await ref.read(locationTrackingServiceProvider).start(
                            technicianId: user.uid,
                            bookingId: booking.id,
                            branchId: user.branchId,
                          );
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start journey'),
                  ),
                if (booking.status == BookingStatus.onTheWay &&
                    !trackingThisBooking)
                  FilledButton.tonalIcon(
                    onPressed: user == null
                        ? null
                        : () => ref.read(locationTrackingServiceProvider).start(
                              technicianId: user.uid,
                              bookingId: booking.id,
                              branchId: user.branchId,
                            ),
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Resume tracking'),
                  ),
                if (booking.status == BookingStatus.onTheWay)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      canMarkArrived
                          ? FilledButton.icon(
                              onPressed: user == null
                                  ? null
                                  : () async {
                                      await bookingRepository()
                                          .markTechnicianReachedCustomer(
                                        bookingId: booking.id,
                                        technicianId: user.uid,
                                      );
                                      await ref
                                          .read(locationTrackingServiceProvider)
                                          .finishBooking();
                                    },
                              icon: const Icon(Icons.location_on_outlined),
                              label: const Text('Mark arrived'),
                            )
                          : OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.near_me_disabled_outlined),
                              label: Text(arrivalGateLabel),
                            ),
                      OutlinedButton.icon(
                        onPressed: user == null || !trackingThisBooking
                            ? null
                            : () async {
                                await bookingRepository()
                                    .markTechnicianReachedCustomer(
                                  bookingId: booking.id,
                                  technicianId: user.uid,
                                  manualOverride: true,
                                );
                                await ref
                                    .read(locationTrackingServiceProvider)
                                    .stop();
                              },
                        icon: const Icon(Icons.person_pin_circle_outlined),
                        label: const Text('Reached customer'),
                      ),
                    ],
                  ),
                if (booking.status == BookingStatus.arrived)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Waiting for customer confirmation'),
                  ),
                if (booking.status == BookingStatus.customerConfirmedArrival)
                  FilledButton.icon(
                    onPressed: () => _showEstimateDialog(context, ref),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Create estimate'),
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
                        : () => bookingRepository().transitionStatus(
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
                      await bookingRepository().transitionStatus(
                        bookingId: booking.id,
                        technicianId: user.uid,
                        expected: BookingStatus.serviceStarted,
                        next: BookingStatus.serviceCompleted,
                      );
                      await ref.read(locationTrackingServiceProvider).stop();
                      await ref
                          .read(technicianRepositoryProvider)
                          .stopSharingLocation(user.uid);
                    },
                    icon: const Icon(Icons.done_all),
                    label: const Text('Complete'),
                  ),
                if (booking.status == BookingStatus.onHold)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text(
                      booking.holdReason == null || booking.holdReason!.isEmpty
                          ? 'On hold by admin'
                          : 'On hold: ${booking.holdReason}',
                    ),
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
                    FilledButton.icon(
                      onPressed: user == null
                          ? null
                          : () => ref
                              .read(billRepositoryProvider)
                              .confirmCollectedPayment(
                                bookingId: booking.id,
                                technicianId: user.uid,
                                paymentMode: bill.paymentMode ?? 'other',
                              ),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(
                        'Confirm ${bill.paymentModeLabel} payment',
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
                              ),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Confirm payment ${_formatBillAmount(bill)}'),
                    ),
                ],
                OutlinedButton.icon(
                    onPressed: booking.status == BookingStatus.arrived ||
                            booking.status ==
                                BookingStatus.customerConfirmedArrival
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

  Future<void> _showPaymentDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Booking booking,
    required String technicianId,
  }) async {
    var selectedMode = 'cash';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Confirm customer payment'),
          content: SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
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
                setDialogState(() => selectedMode = value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(billRepositoryProvider).confirmCollectedPayment(
                      bookingId: booking.id,
                      technicianId: technicianId,
                      paymentMode: selectedMode,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment confirmed and job closed.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Confirm payment'),
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
        height: 168,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
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

String _formatRouteDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

class _AttendanceViewState extends ConsumerState<_AttendanceView> {
  bool _loading = false;
  bool _enrolling = false;
  bool _marked = false;
  String? _result;

  void _setViewState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
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
      if (bytes.length > 5 * 1024 * 1024) {
        _setViewState(() {
          _result =
              'Reference selfie is too large. Please choose a photo under 5 MB.';
        });
        return;
      }
      final faceService = const FaceMatchService();
      final signature = await faceService.createSignature(bytes);
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
        _result =
            'Face ID reference was not saved. Please try again. ${e.toString()}';
      });
    } finally {
      _setViewState(() => _enrolling = false);
    }
  }

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
      if (bytes.length > 650 * 1024) {
        _setViewState(() {
          _result =
              'Selfie image is too large. Please choose a smaller selfie photo.';
        });
        return;
      }
      final contentType = image.mimeType ?? 'image/jpeg';
      final selfieDataUrl = 'data:$contentType;base64,${base64Encode(bytes)}';
      _setViewState(() => _result = 'Getting attendance location...');
      final position = await _attendancePosition();
      if (!mounted) return;
      if (position == null) {
        _setViewState(() {
          _result =
              'Location permission is needed to mark attendance with time and place.';
        });
        return;
      }
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
      if (!match.passed) {
        await ref.read(technicianRepositoryProvider).markAttendance(
              Attendance(
                id: '',
                technicianId: user.uid,
                selfieUrl: selfieDataUrl,
                latitude: position.latitude,
                longitude: position.longitude,
                timestamp: now,
                status: 'face_failed',
                faceMatchPassed: false,
                geofencePassed: geofencePassed,
                faceMatchScore: match.score,
                branchId: user.branchId,
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
              selfieUrl: selfieDataUrl,
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: now,
              status: attendanceStatus,
              faceMatchPassed: true,
              geofencePassed: geofencePassed,
              faceMatchScore: match.score,
              branchId: user.branchId,
            ),
          );

      var trackingMessage = ' GPS tracking is active from 9:20 AM to 10:00 PM.';
      try {
        await ref.read(locationTrackingServiceProvider).startWorkingDay(
              technicianId: user.uid,
              branchId: user.branchId,
            );
      } catch (error) {
        trackingMessage = ' GPS tracking could not start: $error';
      }

      _setViewState(() {
        _marked = true;
        _result =
            '$attendanceStatusLabel marked for today. Face ID score ${(match.score * 100).round()}%.$trackingMessage';
      });
    } catch (e) {
      _setViewState(() {
        _marked = false;
        _result =
            'Attendance was not sent. Please check your connection and try again. ${e.toString()}';
      });
    } finally {
      _setViewState(() => _loading = false);
    }
  }

  Future<Position?> _attendancePosition() async {
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
              Text('Face ID attendance; late uploads are marked absent',
                  style: TextStyle(color: Colors.white70)),
            ],
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
                  '$windowText. Uploads after this are saved as absent.',
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
                    'Please upload a selfie photo. Uploads after the cutoff are saved as absent.',
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
                        'Mark attendance with your registered Face ID selfie.',
                    textAlign: TextAlign.center),
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
                  onPressed: _loading || _enrolling ? null : _markAttendance,
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
        const SizedBox(height: 16),
        _TechnicianAttendanceHistory(attendanceAsync: attendanceAsync),
      ],
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
      BookingStatus.customerConfirmedArrival,
      BookingStatus.estimateSent,
      BookingStatus.estimateRejected,
      BookingStatus.estimateApproved,
      BookingStatus.serviceStarted,
      BookingStatus.onHold,
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
