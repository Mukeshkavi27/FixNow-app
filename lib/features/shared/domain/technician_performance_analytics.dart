import '../../../core/branches/branch_info.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/domain/booking.dart';
import 'bill.dart';
import 'review.dart';

class TechnicianPerformanceAnalytics {
  const TechnicianPerformanceAnalytics({
    required this.leaderboard,
    required this.branchRanking,
    required this.totalRevenue,
    required this.totalCompletedJobs,
    required this.averageRating,
    required this.averageCompletionRate,
    required this.customerSatisfaction,
  });

  final List<TechnicianPerformanceRecord> leaderboard;
  final List<BranchPerformanceRecord> branchRanking;
  final double totalRevenue;
  final int totalCompletedJobs;
  final double averageRating;
  final double averageCompletionRate;
  final double customerSatisfaction;

  List<TechnicianPerformanceRecord> get topPerformers =>
      leaderboard.take(3).toList();

  List<TechnicianPerformanceRecord> get lowestPerformers =>
      leaderboard.reversed.take(3).toList();

  factory TechnicianPerformanceAnalytics.calculate({
    required List<AppUser> technicians,
    required List<Booking> bookings,
    required List<Bill> bills,
    required List<Review> reviews,
    required List<BranchInfo> branches,
    String? branchId,
  }) {
    final bookingById = {for (final booking in bookings) booking.id: booking};
    final scopedTechnicians = technicians.where((technician) {
      return branchId == null ||
          branchId.isEmpty ||
          technician.branchId == branchId;
    }).toList();
    final scopedIds = {
      for (final technician in scopedTechnicians) technician.uid
    };
    final raw = scopedTechnicians.map((technician) {
      final technicianBookings = bookings
          .where((booking) => booking.technicianId == technician.uid)
          .toList();
      final completed = technicianBookings.where(_isCompleted).length;
      final paidBills = bills
          .where((bill) => bill.technicianId == technician.uid && bill.isPaid)
          .toList();
      final technicianReviews = reviews
          .where((review) => review.technicianId == technician.uid)
          .toList();
      final revenue =
          paidBills.fold<double>(0, (sum, bill) => sum + bill.amount);
      final rating = technicianReviews.isEmpty
          ? 0.0
          : technicianReviews.fold<double>(
                0,
                (sum, review) => sum + review.rating,
              ) /
              technicianReviews.length;
      final satisfaction = technicianReviews.isEmpty
          ? 0.0
          : technicianReviews.where((review) => review.rating >= 4).length /
              technicianReviews.length *
              100;
      final completionRate = technicianBookings.isEmpty
          ? 0.0
          : completed / technicianBookings.length * 100;
      return _RawTechnicianPerformance(
        technician: technician,
        revenue: revenue,
        assignedJobs: technicianBookings.length,
        completedJobs: completed,
        averageRating: rating,
        reviewCount: technicianReviews.length,
        completionRate: completionRate,
        customerSatisfaction: satisfaction,
      );
    }).toList();
    final maxRevenue = raw.fold<double>(
      0,
      (maximum, item) => item.revenue > maximum ? item.revenue : maximum,
    );
    final leaderboard = raw.map((item) {
      final revenueScore =
          maxRevenue == 0 ? 0.0 : item.revenue / maxRevenue * 10;
      final score = item.completionRate * 0.35 +
          item.averageRating / 5 * 100 * 0.35 +
          item.customerSatisfaction * 0.20 +
          revenueScore;
      return TechnicianPerformanceRecord(
        technician: item.technician,
        revenue: item.revenue,
        assignedJobs: item.assignedJobs,
        completedJobs: item.completedJobs,
        averageRating: item.averageRating,
        reviewCount: item.reviewCount,
        completionRate: item.completionRate,
        customerSatisfaction: item.customerSatisfaction,
        score: score.clamp(0, 100),
      );
    }).toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : b.revenue.compareTo(a.revenue);
      });

    final branchRanking = branches
        .where((branch) =>
            branchId == null || branchId.isEmpty || branch.id == branchId)
        .map((branch) {
      final branchTechnicians = leaderboard
          .where((record) => record.technician.branchId == branch.id)
          .toList();
      final branchBookings =
          bookings.where((booking) => booking.branchId == branch.id).toList();
      final completed = branchBookings.where(_isCompleted).length;
      final branchBills = bills.where((bill) {
        final resolvedBranch =
            bill.branchId ?? bookingById[bill.bookingId]?.branchId;
        return bill.isPaid && resolvedBranch == branch.id;
      });
      final branchReviews = reviews.where((review) {
        final resolvedBranch =
            review.branchId ?? bookingById[review.bookingId]?.branchId;
        return resolvedBranch == branch.id;
      }).toList();
      final rating = branchReviews.isEmpty
          ? 0.0
          : branchReviews.fold<double>(
                  0, (sum, review) => sum + review.rating) /
              branchReviews.length;
      final satisfaction = branchReviews.isEmpty
          ? 0.0
          : branchReviews.where((review) => review.rating >= 4).length /
              branchReviews.length *
              100;
      final completion = branchBookings.isEmpty
          ? 0.0
          : completed / branchBookings.length * 100;
      final score = branchTechnicians.isEmpty
          ? 0.0
          : branchTechnicians.fold<double>(0, (sum, item) => sum + item.score) /
              branchTechnicians.length;
      return BranchPerformanceRecord(
        branch: branch,
        revenue: branchBills.fold<double>(0, (sum, bill) => sum + bill.amount),
        completedJobs: completed,
        averageRating: rating,
        completionRate: completion,
        customerSatisfaction: satisfaction,
        score: score,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final scopedBookings = bookings
        .where((booking) =>
            booking.technicianId != null &&
            scopedIds.contains(booking.technicianId))
        .toList();
    final scopedReviews = reviews
        .where((review) => scopedIds.contains(review.technicianId))
        .toList();
    final totalCompleted = scopedBookings.where(_isCompleted).length;
    final totalRevenue = bills
        .where((bill) => scopedIds.contains(bill.technicianId) && bill.isPaid)
        .fold<double>(0, (sum, bill) => sum + bill.amount);
    return TechnicianPerformanceAnalytics(
      leaderboard: leaderboard,
      branchRanking: branchRanking,
      totalRevenue: totalRevenue,
      totalCompletedJobs: totalCompleted,
      averageRating: scopedReviews.isEmpty
          ? 0
          : scopedReviews.fold<double>(
                  0, (sum, review) => sum + review.rating) /
              scopedReviews.length,
      averageCompletionRate: scopedBookings.isEmpty
          ? 0
          : totalCompleted / scopedBookings.length * 100,
      customerSatisfaction: scopedReviews.isEmpty
          ? 0
          : scopedReviews.where((review) => review.rating >= 4).length /
              scopedReviews.length *
              100,
    );
  }
}

class TechnicianPerformanceRecord {
  const TechnicianPerformanceRecord({
    required this.technician,
    required this.revenue,
    required this.assignedJobs,
    required this.completedJobs,
    required this.averageRating,
    required this.reviewCount,
    required this.completionRate,
    required this.customerSatisfaction,
    required this.score,
  });
  final AppUser technician;
  final double revenue;
  final int assignedJobs;
  final int completedJobs;
  final double averageRating;
  final int reviewCount;
  final double completionRate;
  final double customerSatisfaction;
  final double score;
}

class BranchPerformanceRecord {
  const BranchPerformanceRecord({
    required this.branch,
    required this.revenue,
    required this.completedJobs,
    required this.averageRating,
    required this.completionRate,
    required this.customerSatisfaction,
    required this.score,
  });
  final BranchInfo branch;
  final double revenue;
  final int completedJobs;
  final double averageRating;
  final double completionRate;
  final double customerSatisfaction;
  final double score;
}

class _RawTechnicianPerformance {
  const _RawTechnicianPerformance({
    required this.technician,
    required this.revenue,
    required this.assignedJobs,
    required this.completedJobs,
    required this.averageRating,
    required this.reviewCount,
    required this.completionRate,
    required this.customerSatisfaction,
  });
  final AppUser technician;
  final double revenue;
  final int assignedJobs;
  final int completedJobs;
  final double averageRating;
  final int reviewCount;
  final double completionRate;
  final double customerSatisfaction;
}

bool _isCompleted(Booking booking) => const {
      BookingStatus.serviceCompleted,
      BookingStatus.billGenerated,
      BookingStatus.closed,
    }.contains(booking.status);
