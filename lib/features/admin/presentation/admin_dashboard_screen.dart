import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../app/widgets/app_scaffold.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/domain/bill.dart';
import '../data/admin_repository.dart';
import '../../technician/data/technician_repository.dart';
import '../../technician/domain/technician_location.dart';
import '../../bookings/presentation/booking_detail_screen.dart';

final allBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingRepositoryProvider).watchAllBookings();
});

final techniciansProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchTechnicians();
});

final customersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchCustomers();
});

final allBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  return ref.watch(billRepositoryProvider).watchAllBills();
});

final activeTechnicianLocationsProvider =
    StreamProvider.autoDispose<List<TechnicianLocation>>((ref) {
  return ref.watch(technicianRepositoryProvider).watchActiveLocations();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(allBookingsProvider);
    final technicians = ref.watch(techniciansProvider);
    final bills = ref.watch(allBillsProvider);
    return AppScaffold(
      title: 'Admin Dashboard',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _manualBooking(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Manual Booking'),
      ),
      body: bookings.when(
        data: (items) {
          final today = DateTime.now();
          final todaysBookings = items.where((booking) {
            return booking.createdAt.year == today.year &&
                booking.createdAt.month == today.month &&
                booking.createdAt.day == today.day;
          }).length;
          final active =
              items.where((b) => b.status != BookingStatus.closed).length;
          final paidBills =
              bills.valueOrNull?.where((bill) => bill.isPaid) ?? const <Bill>[];
          final revenueToday = paidBills
              .where((bill) => _isSameDay(bill.createdAt, today))
              .fold<double>(0, (sum, bill) => sum + bill.amount);
          final revenueMonth = paidBills
              .where((bill) =>
                  bill.createdAt.year == today.year &&
                  bill.createdAt.month == today.month)
              .fold<double>(0, (sum, bill) => sum + bill.amount);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              technicians.when(
                data: (techs) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                        label: "Today's Bookings", value: '$todaysBookings'),
                    _MetricCard(
                        label: 'Active Technicians',
                        value: '${techs.where((t) => t.isActive).length}'),
                    _MetricCard(
                      label: 'Revenue Today',
                      value: 'Rs. ${revenueToday.toStringAsFixed(0)}',
                    ),
                    _MetricCard(
                      label: 'Revenue Month',
                      value: 'Rs. ${revenueMonth.toStringAsFixed(0)}',
                    ),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(error.toString()),
              ),
              const SizedBox(height: 24),
              Text('Booking Management',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...items.map((booking) => _AdminBookingCard(booking: booking)),
              const SizedBox(height: 24),
              Text('Live Monitoring',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const SizedBox(height: 260, child: _TechnicianMap()),
              const SizedBox(height: 24),
              Text('Technician Management',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              technicians.when(
                data: (techs) => Column(
                    children: techs
                        .map((tech) => _TechnicianTile(technician: tech))
                        .toList()),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(error.toString()),
              ),
              Text('Active bookings: $active'),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<void> _manualBooking(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final appliance = TextEditingController();
    final problem = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Manual phone booking'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Customer name'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: appliance,
                      decoration: const InputDecoration(labelText: 'Appliance'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: problem,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Problem description'),
                      validator: _required,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final now = DateTime.now();
                await ref.read(bookingRepositoryProvider).createBooking(
                      Booking(
                        id: '',
                        customerId: 'manual_${const Uuid().v4()}',
                        customerName: name.text.trim(),
                        phone: phone.text.trim(),
                        address: address.text.trim(),
                        applianceType: appliance.text.trim(),
                        problemDescription: problem.text.trim(),
                        preferredDate: now.add(const Duration(days: 1)),
                        preferredTime: 'To be confirmed',
                        status: BookingStatus.booked,
                        createdAt: now,
                      ),
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Create booking'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
      appliance.dispose();
      problem.dispose();
    }
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _AdminBookingCard extends ConsumerWidget {
  const _AdminBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technicians = [
      ...(ref.watch(techniciansProvider).valueOrNull ?? <AppUser>[]),
    ].where((tech) => tech.isActive).toList();
    final locations =
        ref.watch(activeTechnicianLocationsProvider).valueOrNull ??
            <TechnicianLocation>[];
    final locationByTechnician = {
      for (final location in locations) location.technicianId: location,
    };
    if (booking.latitude != null && booking.longitude != null) {
      technicians.sort(
        (left, right) => _distanceToBooking(
          booking,
          locationByTechnician[left.uid],
        ).compareTo(
          _distanceToBooking(booking, locationByTechnician[right.uid]),
        ),
      );
    }
    final bill = ref.watch(bookingBillProvider(booking.id)).valueOrNull;
    final canAssign = booking.status == BookingStatus.booked;
    return Card(
      child: ExpansionTile(
        title: Text('${booking.applianceType} | ${booking.customerName}'),
        subtitle: Text(booking.status.label),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${booking.phone}\n${booking.address}\n${booking.problemDescription}'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: booking.technicianId,
            decoration: InputDecoration(
              labelText: booking.latitude == null
                  ? 'Assign technician'
                  : 'Assign nearest technician',
            ),
            items: technicians
                .map(
                  (tech) => DropdownMenuItem(
                    value: tech.uid,
                    child: Text(
                      _technicianLabel(
                        tech,
                        booking,
                        locationByTechnician[tech.uid],
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: canAssign
                ? (uid) {
                    if (uid == null) return;
                    final tech =
                        technicians.firstWhere((item) => item.uid == uid);
                    ref.read(bookingRepositoryProvider).assignTechnician(
                          bookingId: booking.id,
                          technicianId: tech.uid,
                          technicianName: tech.name,
                        );
                  }
                : null,
          ),
          if (bill != null && !bill.isPaid) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(billRepositoryProvider).markPaid(booking.id),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  'Mark INR ${bill.amount.toStringAsFixed(0)} paid',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static double _distanceToBooking(
    Booking booking,
    TechnicianLocation? location,
  ) {
    if (booking.latitude == null ||
        booking.longitude == null ||
        location == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      booking.latitude!,
      booking.longitude!,
      location.latitude,
      location.longitude,
    );
  }

  static String _technicianLabel(
    AppUser technician,
    Booking booking,
    TechnicianLocation? location,
  ) {
    final distance = _distanceToBooking(booking, location);
    if (distance.isInfinite) return '${technician.name} (location unavailable)';
    return '${technician.name} (${(distance / 1000).toStringAsFixed(1)} km)';
  }
}

class _TechnicianMap extends ConsumerWidget {
  const _TechnicianMap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watchActiveLocations() returns Stream<List<TechnicianLocation>>
    final locations =
        ref.watch(technicianRepositoryProvider).watchActiveLocations();
    return StreamBuilder<List<TechnicianLocation>>(
      stream: locations,
      builder: (context, snapshot) {
        final docs = snapshot.data ?? <TechnicianLocation>[];
        final now = DateTime.now();
        final idle = docs
            .where((location) =>
                location.activeBookingId != null &&
                now.difference(location.updatedAt) >
                    const Duration(minutes: 15))
            .toList();
        final markers = docs.map((loc) {
          final isIdle = idle.any(
            (location) => location.technicianId == loc.technicianId,
          );
          return Marker(
            markerId: MarkerId(loc.technicianId),
            position: LatLng(loc.latitude, loc.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isIdle ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
            ),
            infoWindow: InfoWindow(
              title: loc.technicianId,
              snippet: isIdle ? 'Idle at location for over 15 minutes' : null,
            ),
          );
        }).toSet();
        final center = markers.isEmpty
            ? const LatLng(20.5937, 78.9629)
            : markers.first.position;
        return Column(
          children: [
            if (idle.isNotEmpty)
              MaterialBanner(
                content: Text(
                  '${idle.length} technician(s) have not updated location for over 15 minutes.',
                ),
                leading: const Icon(Icons.warning_amber_rounded),
                actions: const [SizedBox.shrink()],
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: markers.isEmpty ? 4 : 12,
                  ),
                  markers: markers,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TechnicianTile extends ConsumerWidget {
  const _TechnicianTile({required this.technician});

  final AppUser technician;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: SwitchListTile(
        title: Text(technician.name),
        subtitle: Text('${technician.phone} • ${technician.email}'),
        value: technician.isActive,
        onChanged: (value) => ref
            .read(adminRepositoryProvider)
            .setTechnicianActive(technician.uid, value),
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
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
