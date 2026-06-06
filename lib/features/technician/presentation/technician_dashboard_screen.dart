import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../app/widgets/app_scaffold.dart';
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

class TechnicianDashboardScreen extends ConsumerWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(technicianBookingsProvider);
    return AppScaffold(
      title: 'Technician Dashboard',
      actions: [
        IconButton(
          tooltip: 'Mark attendance',
          onPressed: () => _markAttendance(context, ref),
          icon: const Icon(Icons.how_to_reg),
        ),
        IconButton(
          tooltip: 'Share location',
          onPressed: () => _shareLocation(context, ref, null),
          icon: const Icon(Icons.my_location),
        ),
      ],
      body: bookings.when(
        data: (items) {
          final completed = items.where((b) => b.status == BookingStatus.closed).length;
          final active = items.where((b) => b.status != BookingStatus.closed).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(label: 'Assigned Jobs', value: '${active.length}'),
                  _MetricCard(label: 'Completed Jobs', value: '$completed'),
                  _MetricCard(label: 'Monthly Earnings', value: 'Rs. --'),
                ],
              ),
              const SizedBox(height: 20),
              Text('Assigned Jobs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (active.isEmpty) const ListTile(title: Text('No assigned jobs')),
              ...active.map((booking) => _TechnicianJobCard(booking: booking)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location shared')));
    }
  }

  static Future<void> _markAttendance(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final position = await _position();
    final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
    if (user == null || position == null || image == null) return;
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
          ),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance marked')));
    }
  }
}

class _TechnicianJobCard extends ConsumerWidget {
  const _TechnicianJobCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookingRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(booking.applianceType),
              subtitle: Text('${booking.customerName}\n${booking.address}'),
              isThreeLine: true,
              trailing: Chip(label: Text(booking.status.label)),
              onTap: () => context.push('/booking/${booking.id}'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => repo.updateStatus(booking.id, BookingStatus.accepted),
                  icon: const Icon(Icons.check),
                  label: const Text('Accept'),
                ),
                OutlinedButton.icon(
                  onPressed: () => repo.updateStatus(booking.id, BookingStatus.booked),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    repo.updateStatus(booking.id, BookingStatus.onTheWay);
                    TechnicianDashboardScreen._shareLocation(context, ref, booking.id);
                  },
                  icon: const Icon(Icons.navigation),
                  label: const Text('On The Way'),
                ),
                OutlinedButton.icon(
                  onPressed: () => repo.updateStatus(booking.id, BookingStatus.arrived),
                  icon: const Icon(Icons.place),
                  label: const Text('Arrived'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showEstimateDialog(context, ref, booking.id),
                  icon: const Icon(Icons.request_quote),
                  label: const Text('Estimate'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _uploadServicePhoto(context, ref, 'during_service'),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Photo'),
                ),
                FilledButton.icon(
                  onPressed: () => repo.updateStatus(booking.id, BookingStatus.serviceCompleted),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Complete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEstimateDialog(BuildContext context, WidgetRef ref, String bookingId) async {
    final labour = TextEditingController();
    final parts = TextEditingController();
    final notes = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Estimate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: labour, decoration: const InputDecoration(labelText: 'Labour Charge')),
            const SizedBox(height: 12),
            TextField(controller: parts, decoration: const InputDecoration(labelText: 'Parts Charge')),
            const SizedBox(height: 12),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider).valueOrNull!;
              await ref.read(estimateRepositoryProvider).createEstimate(
                    Estimate(
                      id: '',
                      bookingId: bookingId,
                      technicianId: user.uid,
                      labourCharge: double.tryParse(labour.text) ?? 0,
                      partsCharge: double.tryParse(parts.text) ?? 0,
                      notes: notes.text.trim(),
                      isApproved: false,
                      createdAt: DateTime.now(),
                    ),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadServicePhoto(BuildContext context, WidgetRef ref, String folder) async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75);
    if (image == null) return;
    await ref.read(storageRepositoryProvider).uploadFile(
          file: File(image.path),
          folder: folder,
          fileName: '${const Uuid().v4()}.jpg',
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
    }
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
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
