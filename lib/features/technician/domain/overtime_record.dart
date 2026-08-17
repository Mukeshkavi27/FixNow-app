import 'package:cloud_firestore/cloud_firestore.dart';

import '../../bookings/domain/booking.dart';
import '../../shared/domain/bill.dart';

const technicianOvertimeStartHour = 22;

DateTime technicianOvertimeStart(DateTime day) =>
    DateTime(day.year, day.month, day.day, technicianOvertimeStartHour);

DateTime technicianTrackingDayEnd(DateTime day) =>
    DateTime(day.year, day.month, day.day, technicianOvertimeStartHour);

bool isTechnicianOvertime(DateTime timestamp) =>
    !timestamp.isBefore(technicianOvertimeStart(timestamp)) &&
    timestamp.isBefore(technicianTrackingDayEnd(timestamp));

String overtimeDayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class OvertimeRecord {
  const OvertimeRecord({
    required this.id,
    required this.technicianId,
    required this.branchId,
    required this.dateKey,
    required this.startedAt,
    required this.lastDetectedAt,
    required this.isActive,
    this.extraBookingIds = const [],
  });

  final String id;
  final String technicianId;
  final String branchId;
  final String dateKey;
  final DateTime startedAt;
  final DateTime lastDetectedAt;
  final bool isActive;
  final List<String> extraBookingIds;

  Duration get duration {
    final value = lastDetectedAt.difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  factory OvertimeRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return OvertimeRecord(
      id: doc.id,
      technicianId: data['technicianId'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      dateKey: data['dateKey'] as String? ?? '',
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastDetectedAt:
          (data['lastDetectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] as bool? ?? false,
      extraBookingIds: (data['extraBookingIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

class OvertimeSummary {
  const OvertimeSummary({
    required this.duration,
    required this.extraBookings,
    required this.extraRevenue,
  });

  final Duration duration;
  final int extraBookings;
  final double extraRevenue;
}

OvertimeSummary summarizeOvertime({
  required OvertimeRecord record,
  required List<Booking> bookings,
  required List<Bill> bills,
}) {
  final ids = record.extraBookingIds.toSet();
  final matchedBookings = bookings
      .where((booking) {
        if (booking.technicianId != record.technicianId) return false;
        return ids.contains(booking.id) ||
            (overtimeDayKey(booking.updatedAt) == record.dateKey &&
                isTechnicianOvertime(booking.updatedAt));
      })
      .map((booking) => booking.id)
      .toSet();
  final revenue = bills.where((bill) {
    return bill.technicianId == record.technicianId &&
        bill.isPaid &&
        matchedBookings.contains(bill.bookingId);
  }).fold<double>(0, (total, bill) => total + bill.amount);
  return OvertimeSummary(
    duration: record.duration,
    extraBookings: matchedBookings.length,
    extraRevenue: revenue,
  );
}

String formatOvertimeDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}
