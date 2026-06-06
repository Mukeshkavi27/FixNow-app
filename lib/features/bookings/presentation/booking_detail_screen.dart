import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/enums/booking_status.dart';
import '../../auth/data/auth_repository.dart';
import '../../estimates/data/estimate_repository.dart';
import '../../shared/data/review_repository.dart';
import '../data/booking_repository.dart';

final bookingDetailProvider = StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(bookingRepositoryProvider).watchBooking(id);
});

final bookingEstimateProvider = StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(estimateRepositoryProvider).watchForBooking(id);
});

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  final _review = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingDetailProvider(widget.bookingId));
    final estimateAsync = ref.watch(bookingEstimateProvider(widget.bookingId));
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Service Details')),
      body: bookingAsync.when(
        data: (booking) {
          if (booking == null) return const Center(child: Text('Booking not found'));
          final markers = <Marker>{};
          if (booking.latitude != null && booking.longitude != null) {
            markers.add(
              Marker(
                markerId: const MarkerId('service-location'),
                position: LatLng(booking.latitude!, booking.longitude!),
                infoWindow: InfoWindow(title: booking.address),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.applianceType, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Chip(label: Text(booking.status.label)),
                      const SizedBox(height: 12),
                      _Info('Customer', booking.customerName),
                      _Info('Phone', booking.phone),
                      _Info('Address', booking.address),
                      _Info('Problem', booking.problemDescription),
                      _Info('Preferred Time', booking.preferredTime),
                      if (booking.technicianName != null) _Info('Technician', booking.technicianName!),
                      if (booking.imageUrl != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(booking.imageUrl!, height: 180, fit: BoxFit.cover),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (booking.latitude != null && booking.longitude != null)
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(booking.latitude!, booking.longitude!),
                        zoom: 14,
                      ),
                      markers: markers,
                      myLocationButtonEnabled: false,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              estimateAsync.when(
                data: (estimate) {
                  if (estimate == null) return const SizedBox.shrink();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estimate', style: Theme.of(context).textTheme.titleLarge),
                          _Info('Labour Charge', 'Rs. ${estimate.labourCharge.toStringAsFixed(2)}'),
                          _Info('Parts Charge', 'Rs. ${estimate.partsCharge.toStringAsFixed(2)}'),
                          _Info('Total', 'Rs. ${estimate.total.toStringAsFixed(2)}'),
                          _Info('Notes', estimate.notes),
                          if (!estimate.isApproved && user?.uid == booking.customerId)
                            FilledButton.icon(
                              onPressed: () => ref
                                  .read(estimateRepositoryProvider)
                                  .approve(estimate.id, booking.id),
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Approve Estimate'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(error.toString()),
              ),
              const SizedBox(height: 12),
              if (booking.status == BookingStatus.serviceCompleted && user?.uid == booking.customerId)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Review Service', style: Theme.of(context).textTheme.titleLarge),
                        DropdownButtonFormField<int>(
                          value: _rating,
                          decoration: const InputDecoration(labelText: 'Rating'),
                          items: [1, 2, 3, 4, 5]
                              .map((value) => DropdownMenuItem(value: value, child: Text('$value stars')))
                              .toList(),
                          onChanged: (value) => setState(() => _rating = value ?? 5),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _review,
                          decoration: const InputDecoration(labelText: 'Review text'),
                          minLines: 2,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: booking.technicianId == null
                              ? null
                              : () => ref.read(reviewRepositoryProvider).submitReview(
                                    bookingId: booking.id,
                                    technicianId: booking.technicianId!,
                                    customerId: booking.customerId,
                                    rating: _rating,
                                    text: _review.text.trim(),
                                  ),
                          icon: const Icon(Icons.star),
                          label: const Text('Submit Review'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: [TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w400))],
        ),
      ),
    );
  }
}
