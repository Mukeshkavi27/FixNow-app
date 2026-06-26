import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

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
  const BookingDetailScreen({
    required this.bookingId,
    this.showConfirmation = false,
    super.key,
  });

  final String bookingId;
  final bool showConfirmation;

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
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Appliance Service Details'),
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
          final canHaveEstimate =
              booking.status.index >= BookingStatus.estimateSent.index;
          final canHaveBill =
              booking.status.index >= BookingStatus.billGenerated.index;
          final canHaveReview =
              booking.status.index >= BookingStatus.serviceCompleted.index;
          final estimateAsync = canHaveEstimate
              ? ref.watch(bookingEstimateProvider(widget.bookingId))
              : const AsyncValue.data(null);
          final billAsync = canHaveBill
              ? ref.watch(bookingBillProvider(widget.bookingId))
              : const AsyncValue.data(null);
          final reviewAsync = canHaveReview
              ? ref.watch(bookingReviewProvider(widget.bookingId))
              : const AsyncValue.data(null);
          final technicianLocation = booking.technicianId == null
              ? null
              : ref
                  .watch(
                    bookingTechnicianLocationProvider(booking.technicianId!),
                  )
                  .valueOrNull;

          final primaryDetails = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showConfirmation) ...[
                _ConfirmationBanner(booking: booking),
                const SizedBox(height: 14),
              ],
              if (user?.uid == booking.customerId &&
                  booking.status == BookingStatus.booked &&
                  booking.technicianId == null) ...[
                _CustomerBookingActions(
                  booking: booking,
                  onReschedule: _rescheduleBooking,
                  onCancel: _cancelBooking,
                ),
                const SizedBox(height: 14),
              ],
              _StatusBanner(status: booking.status),
              const SizedBox(height: 14),
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
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              _serviceAssetName(booking.applianceType),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.home_repair_service_outlined,
                                color: AppTheme.primary,
                                size: 26,
                              ),
                            ),
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
              if (booking.latitude != null && booking.longitude != null) ...[
                const SizedBox(height: 14),
                _UCCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Service location saved',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              booking.address,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );

          final progressDetails = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrackingCard(
                booking: booking,
                technicianLocation: technicianLocation,
              ),
              const SizedBox(height: 14),
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
            ],
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              return ListView(
                padding: EdgeInsets.all(isWide ? 28 : 16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: primaryDetails),
                                const SizedBox(width: 18),
                                Expanded(flex: 2, child: progressDetails),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                primaryDetails,
                                const SizedBox(height: 14),
                                progressDetails,
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }

  Future<void> _rescheduleBooking(dynamic booking) async {
    var selectedDate = booking.preferredDate as DateTime;
    var selectedTime = _parseTimeOfDay(booking.preferredTime);
    final result = await showDialog<({DateTime date, TimeOfDay time})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Reschedule booking'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Preferred date'),
                  subtitle: Text(DateFormat.yMMMd().format(selectedDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                      initialDate: selectedDate,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Preferred time'),
                  subtitle: Text(selectedTime.format(context)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Keep current'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  (date: selectedDate, time: selectedTime),
                ),
                child: const Text('Reschedule'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(bookingRepositoryProvider).rescheduleUnassignedBooking(
            bookingId: booking.id as String,
            customerId: booking.customerId as String,
            preferredDate: result.date,
            preferredTime: result.time.format(context),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking rescheduled.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _cancelBooking(dynamic booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text(
          'You can cancel this booking because a technician has not been assigned yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(bookingRepositoryProvider).cancelUnassignedBooking(
            bookingId: booking.id as String,
            customerId: booking.customerId as String,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
      context.go('/customer/history');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
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

class _ConfirmationBanner extends StatelessWidget {
  const _ConfirmationBanner({required this.booking});

  final dynamic booking;

  @override
  Widget build(BuildContext context) {
    final shortId =
        booking.id.length > 8 ? booking.id.substring(0, 8) : booking.id;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: AppTheme.accent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Booking confirmed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${booking.applianceType} service is scheduled for '
                  '${DateFormat.yMMMd().format(booking.preferredDate)} at '
                  '${booking.preferredTime}.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Booking ID: $shortId',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
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

class _CustomerBookingActions extends StatelessWidget {
  const _CustomerBookingActions({
    required this.booking,
    required this.onReschedule,
    required this.onCancel,
  });

  final dynamic booking;
  final ValueChanged<dynamic> onReschedule;
  final ValueChanged<dynamic> onCancel;

  @override
  Widget build(BuildContext context) {
    return _UCCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Need to change this visit?',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'You can reschedule or cancel until a technician is assigned.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onReschedule(booking),
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('Reschedule'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  onPressed: () => onCancel(booking),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({
    required this.booking,
    required this.technicianLocation,
  });

  final dynamic booking;
  final TechnicianLocation? technicianLocation;

  @override
  Widget build(BuildContext context) {
    final hasServiceLocation =
        booking.latitude != null && booking.longitude != null;
    final hasTechnicianLocation = technicianLocation != null;
    final isAssigned = booking.technicianName != null;
    final title = hasTechnicianLocation
        ? 'Technician is on the map'
        : isAssigned
            ? 'Technician assigned'
            : 'Technician assignment pending';
    final subtitle = hasTechnicianLocation
        ? 'Live location updates will refresh as the technician moves.'
        : isAssigned
            ? '${booking.technicianName} will share live location when travel starts.'
            : 'We will assign a technician before the scheduled visit.';

    return _UCCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TrackingSteps(status: booking.status),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: hasServiceLocation
                  ? _TrackingMap(
                      serviceLatitude: booking.latitude!,
                      serviceLongitude: booking.longitude!,
                      technicianLocation: technicianLocation,
                    )
                  : const _MapPlaceholder(),
            ),
          ),
          const SizedBox(height: 12),
          _TechnicianSummary(
            technicianName: booking.technicianName,
            updatedAt: technicianLocation?.updatedAt,
          ),
        ],
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  const _TrackingMap({
    required this.serviceLatitude,
    required this.serviceLongitude,
    required this.technicianLocation,
  });

  final double serviceLatitude;
  final double serviceLongitude;
  final TechnicianLocation? technicianLocation;

  @override
  Widget build(BuildContext context) {
    final servicePosition = LatLng(serviceLatitude, serviceLongitude);
    final techPosition = technicianLocation == null
        ? null
        : LatLng(technicianLocation!.latitude, technicianLocation!.longitude);
    return FlutterMap(
      options: MapOptions(
        initialCenter: techPosition ?? servicePosition,
        initialZoom: techPosition == null ? 14 : 12,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.fixnow.app',
        ),
        if (techPosition != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [techPosition, servicePosition],
                color: AppTheme.primary,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: servicePosition,
              width: 48,
              height: 48,
              child: const _TrackingMarker(
                icon: Icons.home_repair_service_outlined,
                color: AppTheme.accent,
              ),
            ),
            if (techPosition != null)
              Marker(
                point: techPosition,
                width: 48,
                height: 48,
                child: const _TrackingMarker(
                  icon: Icons.engineering_outlined,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrackingMarker extends StatelessWidget {
  const _TrackingMarker({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(18),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: AppTheme.primary, size: 34),
            SizedBox(height: 8),
            Text(
              'Map tracking will start after service location is available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnicianSummary extends StatelessWidget {
  const _TechnicianSummary({
    required this.technicianName,
    required this.updatedAt,
  });

  final String? technicianName;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary,
            child: Icon(Icons.engineering_outlined, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  technicianName ?? 'Technician will be assigned soon',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  updatedAt == null
                      ? 'Live tracking pending'
                      : 'Location updated ${DateFormat.jm().format(updatedAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
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

class _TrackingSteps extends StatelessWidget {
  const _TrackingSteps({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (BookingStatus.booked, 'Booked'),
      (BookingStatus.technicianAssigned, 'Assigned'),
      (BookingStatus.onTheWay, 'On way'),
      (BookingStatus.arrived, 'Arrived'),
      (BookingStatus.serviceCompleted, 'Done'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: status.index >= steps[i].$1.index
                        ? AppTheme.accent
                        : AppTheme.divider,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    status.index >= steps[i].$1.index
                        ? Icons.check
                        : Icons.circle,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  steps[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (i != steps.length - 1)
            Container(
              width: 14,
              height: 2,
              color: status.index >= steps[i + 1].$1.index
                  ? AppTheme.accent
                  : AppTheme.divider,
            ),
        ],
      ],
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
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BookingStatus.closed => Colors.green,
      BookingStatus.booked => AppTheme.badgeOrange,
      BookingStatus.serviceStarted ||
      BookingStatus.serviceCompleted ||
      BookingStatus.billGenerated =>
        AppTheme.accent,
      _ => AppTheme.primary,
    };
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
            status.label,
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

String _serviceAssetName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('air conditioner') ||
      normalized == 'ac' ||
      normalized.contains('ac repair')) {
    return 'assets/images/ac.png';
  }
  if (normalized.contains('refrigerator') || normalized.contains('fridge')) {
    return 'assets/images/refrigerator.png';
  }
  if (normalized.contains('washing')) {
    return 'assets/images/washing_machine.png';
  }
  if (normalized.contains('microwave')) {
    return 'assets/images/microwave.png';
  }
  if (normalized.contains('purifier')) {
    return 'assets/images/water_purifier.png';
  }
  if (normalized.contains('television') || normalized.contains('tv')) {
    return 'assets/images/television.png';
  }
  if (normalized.contains('fan')) return 'assets/images/fan.png';
  return 'assets/images/other_services.png';
}

TimeOfDay _parseTimeOfDay(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([AP]M)?$', caseSensitive: false)
      .firstMatch(trimmed);
  if (match == null) return const TimeOfDay(hour: 10, minute: 0);
  var hour = int.tryParse(match.group(1) ?? '') ?? 10;
  final minute = int.tryParse(match.group(2) ?? '') ?? 0;
  final period = match.group(3)?.toUpperCase();
  if (period == 'PM' && hour < 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
}
