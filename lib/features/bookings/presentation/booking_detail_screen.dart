import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/data/auth_repository.dart';
import '../../estimates/data/estimate_repository.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/data/review_repository.dart';
import '../../technician/data/technician_repository.dart';
import '../../technician/domain/technician_location.dart';
import '../data/booking_repository.dart';

final bookingDetailProvider =
    StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(bookingRepositoryProvider).watchBooking(id);
});

final bookingEstimateProvider =
    StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(estimateRepositoryProvider).watchForBooking(id);
});

final bookingBillProvider = StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(billRepositoryProvider).watchForBooking(id);
});

final bookingReviewProvider =
    StreamProvider.autoDispose.family((ref, String id) {
  return ref.watch(reviewRepositoryProvider).watchForBooking(id);
});

final bookingTechnicianLocationProvider = StreamProvider.autoDispose
    .family<TechnicianLocation?, String>((ref, technicianId) {
  return ref.watch(technicianRepositoryProvider).watchLocation(technicianId);
});

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
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
    final billAsync = ref.watch(bookingBillProvider(widget.bookingId));
    final reviewAsync = ref.watch(bookingReviewProvider(widget.bookingId));
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Service Details'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: bookingAsync.when(
        data: (booking) {
          if (booking == null) {
            return const Center(child: Text('Booking not found'));
          }
          final technicianLocation = booking.technicianId == null
              ? null
              : ref
                  .watch(
                    bookingTechnicianLocationProvider(booking.technicianId!),
                  )
                  .valueOrNull;
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
          if (technicianLocation != null) {
            markers.add(
              Marker(
                markerId: const MarkerId('technician-location'),
                position: LatLng(
                  technicianLocation.latitude,
                  technicianLocation.longitude,
                ),
                infoWindow: const InfoWindow(title: 'Technician'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status chip
              _StatusBanner(status: booking.status),
              const SizedBox(height: 14),

              // Main info card
              _UCCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: const Icon(
                            Icons.home_repair_service_outlined,
                            color: AppTheme.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.applianceType,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Booked for ${booking.preferredTime}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 14),
                    _InfoRow(
                      icon: Icons.person_outline,
                      label: 'Customer',
                      value: booking.customerName,
                    ),
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: booking.phone,
                    ),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: booking.address,
                    ),
                    _InfoRow(
                      icon: Icons.description_outlined,
                      label: 'Problem',
                      value: booking.problemDescription,
                    ),
                    if (booking.technicianName != null)
                      _InfoRow(
                        icon: Icons.engineering_outlined,
                        label: 'Technician',
                        value: booking.technicianName!,
                      ),
                  ],
                ),
              ),

              if (booking.imageUrl != null) ...[
                const SizedBox(height: 14),
                _UCCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Appliance photo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          booking.imageUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (booking.servicePhotos.isNotEmpty) ...[
                const SizedBox(height: 14),
                _UCCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Service photos',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 128,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: booking.servicePhotos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final photo = booking.servicePhotos[index];
                            return SizedBox(
                              width: 150,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.network(
                                        photo.url,
                                        width: 150,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const ColoredBox(
                                          color: AppTheme.surface,
                                          child: Center(
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    photo.stage.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (markers.isNotEmpty) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 200,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          technicianLocation?.latitude ?? booking.latitude!,
                          technicianLocation?.longitude ?? booking.longitude!,
                        ),
                        zoom: 14,
                      ),
                      markers: markers,
                      myLocationButtonEnabled: false,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Estimate card
              estimateAsync.when(
                data: (estimate) {
                  if (estimate == null) return const SizedBox.shrink();
                  return _UCCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Service Estimate',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (estimate.isApproved)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green.shade200),
                                ),
                                child: const Text(
                                  'Approved',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _EstimateRow(
                            label: 'Labour charge',
                            value:
                                '₹${estimate.labourCharge.toStringAsFixed(0)}'),
                        _EstimateRow(
                            label: 'Parts charge',
                            value:
                                '₹${estimate.partsCharge.toStringAsFixed(0)}'),
                        const Divider(height: 20),
                        _EstimateRow(
                          label: 'Total',
                          value: '₹${estimate.total.toStringAsFixed(0)}',
                          bold: true,
                        ),
                        if (estimate.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            estimate.notes,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                        if (!estimate.isApproved &&
                            user?.uid == booking.customerId) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => ref
                                  .read(estimateRepositoryProvider)
                                  .approve(estimate.id, booking.id),
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 18),
                              label: const Text('Approve Estimate',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(e.toString()),
              ),

              billAsync.when(
                data: (bill) {
                  if (bill == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _UCCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Final bill',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  'INR ${bill.amount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(bill.isPaid ? 'Paid' : 'Payment due'),
                            backgroundColor: bill.isPaid
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Unable to load bill: $error'),
                ),
              ),

              // Review section
              if (booking.status.index >=
                      BookingStatus.serviceCompleted.index &&
                  user?.uid == booking.customerId) ...[
                const SizedBox(height: 14),
                if (reviewAsync.valueOrNull != null)
                  _UCCard(
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Review submitted: ${reviewAsync.valueOrNull!.rating}/5',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _UCCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate this service',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Star selector
                        Row(
                          children: List.generate(
                            5,
                            (i) => GestureDetector(
                              onTap: () => setState(() => _rating = i + 1),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  i < _rating ? Icons.star : Icons.star_border,
                                  size: 32,
                                  color: i < _rating
                                      ? AppTheme.starColor
                                      : AppTheme.divider,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _review,
                          minLines: 2,
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Share your experience...',
                            hintStyle: const TextStyle(
                                color: AppTheme.textHint, fontSize: 13),
                            filled: true,
                            fillColor: AppTheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: booking.technicianId == null
                                ? null
                                : () => ref
                                    .read(reviewRepositoryProvider)
                                    .submitReview(
                                      bookingId: booking.id,
                                      technicianId: booking.technicianId!,
                                      customerId: booking.customerId,
                                      rating: _rating,
                                      text: _review.text.trim(),
                                    ),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Submit Review',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        if (booking.technicianId == null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'A review can be submitted once a technician has been assigned to this booking.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 32),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}

class _UCCard extends StatelessWidget {
  const _UCCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textHint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textHint,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
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

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: bold ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final dynamic status;

  @override
  Widget build(BuildContext context) {
    Color getColor() {
      final n = status.name as String;
      if (n == 'closed') return Colors.green;
      if (n == 'booked') return AppTheme.badgeOrange;
      if (n.contains('service') || n.contains('bill')) return AppTheme.accent;
      return AppTheme.primary;
    }

    final color = getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            status.label as String,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}