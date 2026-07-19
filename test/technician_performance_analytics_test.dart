import 'package:fixnow/core/branches/branch_info.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/bookings/domain/booking.dart';
import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/review.dart';
import 'package:fixnow/features/shared/domain/technician_performance_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 14);
  const chennai = BranchInfo(
    id: 'chennai',
    name: 'FixNow Chennai',
    city: 'Chennai',
    latitude: 13.08,
    longitude: 80.27,
  );
  const bengaluru = BranchInfo(
    id: 'bengaluru',
    name: 'FixNow Bengaluru',
    city: 'Bengaluru',
    latitude: 12.97,
    longitude: 77.59,
  );
  AppUser technician(String id, String name, BranchInfo branch) => AppUser(
        uid: id,
        name: name,
        email: '$id@test.dev',
        phone: '9999999999',
        role: UserRole.technician,
        accountStatus: AccountStatus.approved,
        branchId: branch.id,
        branchName: branch.name,
        createdAt: now,
        isActive: true,
      );
  final technicians = [
    technician('tech-1', 'Ravi', chennai),
    technician('tech-2', 'Meena', chennai),
    technician('tech-3', 'Arjun', bengaluru),
  ];
  Booking booking(String id, String technicianId, BranchInfo branch,
          BookingStatus status) =>
      Booking(
        id: id,
        customerId: 'customer-$id',
        customerName: 'Customer $id',
        phone: '9999999998',
        address: branch.city,
        applianceType: 'Air Conditioner',
        problemDescription: 'Service',
        preferredDate: now,
        preferredTime: '10:00 AM',
        status: status,
        createdAt: now,
        technicianId: technicianId,
        branchId: branch.id,
        branchName: branch.name,
      );
  final bookings = [
    booking('a1', 'tech-1', chennai, BookingStatus.closed),
    booking('a2', 'tech-1', chennai, BookingStatus.billGenerated),
    booking('a3', 'tech-1', chennai, BookingStatus.serviceStarted),
    booking('a4', 'tech-2', chennai, BookingStatus.closed),
    booking('a5', 'tech-2', chennai, BookingStatus.estimateRejected),
    booking('b1', 'tech-3', bengaluru, BookingStatus.closed),
    booking('b2', 'tech-3', bengaluru, BookingStatus.serviceCompleted),
  ];
  Bill bill(String bookingId, String technicianId, String branchId,
          double amount) =>
      Bill(
        id: bookingId,
        bookingId: bookingId,
        customerId: 'customer-$bookingId',
        technicianId: technicianId,
        branchId: branchId,
        amount: amount,
        createdAt: now,
        paidAt: now,
        isPaid: true,
      );
  final bills = [
    bill('a1', 'tech-1', chennai.id, 3000),
    bill('a2', 'tech-1', chennai.id, 2000),
    bill('a4', 'tech-2', chennai.id, 2000),
    bill('b1', 'tech-3', bengaluru.id, 3500),
    bill('b2', 'tech-3', bengaluru.id, 2500),
  ];
  Review review(
          String bookingId, String technicianId, String branchId, int rating) =>
      Review(
        id: bookingId,
        bookingId: bookingId,
        technicianId: technicianId,
        customerId: 'customer-$bookingId',
        branchId: branchId,
        rating: rating,
        text: 'Review',
        createdAt: now,
      );
  final reviews = [
    review('a1', 'tech-1', chennai.id, 5),
    review('a2', 'tech-1', chennai.id, 4),
    review('a4', 'tech-2', chennai.id, 2),
    review('a5', 'tech-2', chennai.id, 3),
    review('b1', 'tech-3', bengaluru.id, 5),
  ];

  test('calculates performance metrics and stable leaderboard order', () {
    final analytics = TechnicianPerformanceAnalytics.calculate(
      technicians: technicians,
      bookings: bookings,
      bills: bills,
      reviews: reviews,
      branches: const [chennai, bengaluru],
    );

    expect(analytics.totalRevenue, 13000);
    expect(analytics.totalCompletedJobs, 5);
    expect(analytics.averageRating, closeTo(3.8, 0.001));
    expect(analytics.averageCompletionRate, closeTo(71.43, 0.01));
    expect(analytics.customerSatisfaction, 60);
    expect(analytics.leaderboard.first.technician.name, 'Arjun');
    expect(analytics.leaderboard.last.technician.name, 'Meena');
    expect(analytics.leaderboard.first.score, 100);
    expect(analytics.branchRanking.first.branch.name, bengaluru.name);
  });

  test('Branch Admin scope excludes other branch performance', () {
    final analytics = TechnicianPerformanceAnalytics.calculate(
      technicians: technicians,
      bookings: bookings,
      bills: bills,
      reviews: reviews,
      branches: const [chennai, bengaluru],
      branchId: chennai.id,
    );

    expect(analytics.totalRevenue, 7000);
    expect(analytics.totalCompletedJobs, 3);
    expect(analytics.averageRating, 3.5);
    expect(analytics.averageCompletionRate, 60);
    expect(analytics.customerSatisfaction, 50);
    expect(analytics.leaderboard.map((item) => item.technician.name),
        ['Ravi', 'Meena']);
    expect(analytics.branchRanking.single.branch.id, chennai.id);
  });
}
