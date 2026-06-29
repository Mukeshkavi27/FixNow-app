import '../../../core/enums/booking_status.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/domain/bill.dart';
import '../../technician/domain/technician_location.dart';

enum AdminRangeFilter {
  today('Today'),
  week('This week'),
  month('This month'),
  all('All time');

  const AdminRangeFilter(this.label);
  final String label;
}

class TechnicianPerformance {
  const TechnicianPerformance({
    required this.technician,
    required this.dailyEarnings,
    required this.monthlyEarnings,
    required this.completedJobs,
    required this.pendingCollections,
    required this.activeBookings,
    required this.lastLocationUpdate,
    required this.statusLabel,
    required this.highlightRisk,
  });

  final AppUser technician;
  final double dailyEarnings;
  final double monthlyEarnings;
  final int completedJobs;
  final double pendingCollections;
  final int activeBookings;
  final DateTime? lastLocationUpdate;
  final String statusLabel;
  final bool highlightRisk;
}

List<Booking> filterAdminBookings({
  required List<Booking> bookings,
  required DateTime now,
  String query = '',
  BookingStatus? status,
  String? technicianId,
  AdminRangeFilter range = AdminRangeFilter.all,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = bookings.where((booking) {
    final matchesQuery = normalizedQuery.isEmpty ||
        booking.customerName.toLowerCase().contains(normalizedQuery) ||
        booking.applianceType.toLowerCase().contains(normalizedQuery) ||
        booking.address.toLowerCase().contains(normalizedQuery) ||
        booking.phone.toLowerCase().contains(normalizedQuery);
    final matchesStatus = status == null || booking.status == status;
    final matchesTechnician = technicianId == null ||
        technicianId == 'all' ||
        booking.technicianId == technicianId;
    final matchesRange = _matchesRange(
      moment: booking.preferredDate,
      now: now,
      range: range,
    );
    return matchesQuery && matchesStatus && matchesTechnician && matchesRange;
  }).toList();

  filtered.sort((left, right) {
    final leftDeadline = bookingDeadline(left);
    final rightDeadline = bookingDeadline(right);
    if (leftDeadline != null && rightDeadline != null) {
      return leftDeadline.compareTo(rightDeadline);
    }
    if (leftDeadline != null) return -1;
    if (rightDeadline != null) return 1;
    return right.createdAt.compareTo(left.createdAt);
  });
  return filtered;
}

List<TechnicianPerformance> buildTechnicianPerformance({
  required List<AppUser> technicians,
  required List<Bill> bills,
  required List<Booking> bookings,
  required List<TechnicianLocation> locations,
  required DateTime now,
}) {
  final locationByTechnician = {
    for (final location in locations) location.technicianId: location,
  };

  return technicians.map((technician) {
    final technicianBills =
        bills.where((bill) => bill.technicianId == technician.uid).toList();
    final dailyEarnings = technicianBills
        .where((bill) => bill.isPaid && isSameDay(bill.createdAt, now))
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final monthlyEarnings = technicianBills
        .where((bill) =>
            bill.isPaid &&
            bill.createdAt.year == now.year &&
            bill.createdAt.month == now.month)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final pendingCollections = technicianBills
        .where((bill) => !bill.isPaid)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    final completedJobs = technicianBills.where((bill) => bill.isPaid).length;
    final activeBookings = bookings
        .where((booking) =>
            booking.technicianId == technician.uid &&
            isTechnicianBusyStatus(booking.status))
        .length;
    final location = locationByTechnician[technician.uid];
    final isStale = location != null &&
        now.difference(location.updatedAt) > const Duration(minutes: 15);
    final highlightRisk = !technician.isActive || isStale;
    final statusLabel = !technician.isActive
        ? 'Inactive'
        : activeBookings > 0
            ? (isStale ? 'Delayed updates' : 'On active job')
            : (location == null
                ? 'No live location'
                : (isStale ? 'Needs check-in' : 'Available'));
    return TechnicianPerformance(
      technician: technician,
      dailyEarnings: dailyEarnings,
      monthlyEarnings: monthlyEarnings,
      completedJobs: completedJobs,
      pendingCollections: pendingCollections,
      activeBookings: activeBookings,
      lastLocationUpdate: location?.updatedAt,
      statusLabel: statusLabel,
      highlightRisk: highlightRisk,
    );
  }).toList()
    ..sort((left, right) {
      if (left.highlightRisk != right.highlightRisk) {
        return left.highlightRisk ? -1 : 1;
      }
      return right.monthlyEarnings.compareTo(left.monthlyEarnings);
    });
}

DateTime? bookingScheduledAt(Booking booking) {
  final raw = booking.preferredTime.trim();
  if (raw.isEmpty || raw.toLowerCase() == 'to be confirmed') {
    return DateTime(
      booking.preferredDate.year,
      booking.preferredDate.month,
      booking.preferredDate.day,
      12,
    );
  }
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([AP]M)$', caseSensitive: false)
      .firstMatch(raw);
  if (match == null) {
    return DateTime(
      booking.preferredDate.year,
      booking.preferredDate.month,
      booking.preferredDate.day,
      12,
    );
  }

  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final period = match.group(3)!.toUpperCase();
  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  return DateTime(
    booking.preferredDate.year,
    booking.preferredDate.month,
    booking.preferredDate.day,
    hour,
    minute,
  );
}

DateTime? bookingDeadline(Booking booking) {
  if (booking.technicianId == null || booking.status == BookingStatus.closed) {
    return null;
  }
  final scheduledAt = bookingScheduledAt(booking);
  return scheduledAt?.add(const Duration(hours: 2));
}

bool isBookingOverdue(Booking booking, DateTime now) {
  final deadline = bookingDeadline(booking);
  if (deadline == null) return false;
  if (booking.status == BookingStatus.billGenerated ||
      booking.status == BookingStatus.closed) {
    return false;
  }
  return now.isAfter(deadline);
}

bool isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _matchesRange({
  required DateTime moment,
  required DateTime now,
  required AdminRangeFilter range,
}) {
  return switch (range) {
    AdminRangeFilter.today => isSameDay(moment, now),
    AdminRangeFilter.week =>
      moment.isAfter(now.subtract(const Duration(days: 7))) ||
          isSameDay(moment, now.subtract(const Duration(days: 7))),
    AdminRangeFilter.month =>
      moment.year == now.year && moment.month == now.month,
    AdminRangeFilter.all => true,
  };
}
