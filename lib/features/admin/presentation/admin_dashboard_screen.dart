import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/widgets/app_scaffold.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../data/admin_repository.dart';
import '../../technician/data/technician_repository.dart';

final allBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingRepositoryProvider).watchAllBookings();
});

final techniciansProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchTechnicians();
});

final customersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchCustomers();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(allBookingsProvider);
    final technicians = ref.watch(techniciansProvider);
    return AppScaffold(
      title: 'Admin Dashboard',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _manualBooking(context),
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
          final active = items.where((b) => b.status != BookingStatus.closed).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              technicians.when(
                data: (techs) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(label: "Today's Bookings", value: '$todaysBookings'),
                    _MetricCard(label: 'Active Technicians', value: '${techs.where((t) => t.isActive).length}'),
                    const _MetricCard(label: 'Revenue Today', value: 'Rs. --'),
                    const _MetricCard(label: 'Revenue Month', value: 'Rs. --'),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(error.toString()),
              ),
              const SizedBox(height: 24),
              Text('Booking Management', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...items.map((booking) => _AdminBookingCard(booking: booking)),
              const SizedBox(height: 24),
              Text('Live Monitoring', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(height: 260, child: const _TechnicianMap()),
              const SizedBox(height: 24),
              Text('Technician Management', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              technicians.when(
                data: (techs) => Column(children: techs.map((tech) => _TechnicianTile(technician: tech)).toList()),
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

  void _manualBooking(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Use customer booking form or extend this action for call-center intake.')),
    );
  }
}

class _AdminBookingCard extends ConsumerWidget {
  const _AdminBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technicians = ref.watch(techniciansProvider).valueOrNull ?? [];
    return Card(
      child: ExpansionTile(
        title: Text('${booking.applianceType} • ${booking.customerName}'),
        subtitle: Text(booking.status.label),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${booking.phone}\n${booking.address}\n${booking.problemDescription}'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: booking.technicianId,
            decoration: const InputDecoration(labelText: 'Assign nearest technician'),
            items: technicians
                .where((tech) => tech.isActive)
                .map((tech) => DropdownMenuItem(value: tech.uid, child: Text(tech.name)))
                .toList(),
            onChanged: (uid) {
              final tech = technicians.firstWhere((item) => item.uid == uid);
              ref.read(bookingRepositoryProvider).assignTechnician(
                    bookingId: booking.id,
                    technicianId: tech.uid,
                    technicianName: tech.name,
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _TechnicianMap extends ConsumerWidget {
  const _TechnicianMap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(technicianRepositoryProvider).watchActiveLocations();
    return StreamBuilder(
      stream: locations,
      builder: (context, snapshot) {
        final docs = snapshot.data ?? [];
        final markers = docs.map((doc) {
          final data = doc.data();
          return Marker(
            markerId: MarkerId(doc.id),
            position: LatLng((data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble()),
            infoWindow: InfoWindow(title: doc.id),
          );
        }).toSet();
        final center = markers.isEmpty ? const LatLng(20.5937, 78.9629) : markers.first.position;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: markers.isEmpty ? 4 : 12),
            markers: markers,
          ),
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
        onChanged: (value) => ref.read(adminRepositoryProvider).setTechnicianActive(technician.uid, value),
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
