import '../../../core/branches/branch_info.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/domain/booking.dart';
import 'bill.dart';

class RevenueAnalytics {
  const RevenueAnalytics({
    required this.today,
    required this.week,
    required this.month,
    required this.year,
    required this.allTime,
    required this.paidBillCount,
    required this.pendingAmount,
    required this.pendingBillCount,
    required this.dailyTrend,
    required this.monthlyTrend,
    required this.branchRevenue,
    required this.technicianRevenue,
    required this.serviceRevenue,
    required this.reportRows,
    required this.recentPaidBills,
  });

  final double today;
  final double week;
  final double month;
  final double year;
  final double allTime;
  final int paidBillCount;
  final double pendingAmount;
  final int pendingBillCount;
  final List<RevenuePoint> dailyTrend;
  final List<RevenuePoint> monthlyTrend;
  final List<RevenueBreakdown> branchRevenue;
  final List<RevenueBreakdown> technicianRevenue;
  final List<RevenueBreakdown> serviceRevenue;
  final List<RevenueReportRow> reportRows;
  final List<Bill> recentPaidBills;

  factory RevenueAnalytics.calculate({
    required List<Bill> bills,
    required List<Booking> bookings,
    required List<BranchInfo> branches,
    required List<AppUser> technicians,
    required DateTime now,
    String? branchId,
  }) {
    final bookingById = {for (final booking in bookings) booking.id: booking};
    final branchById = {for (final branch in branches) branch.id: branch};
    final technicianById = {
      for (final technician in technicians) technician.uid: technician,
    };
    String? billBranch(Bill bill) =>
        bill.revenueBranchId ??
        bill.branchId ??
        technicianById[bill.technicianId]?.nativeBranchId ??
        technicianById[bill.technicianId]?.branchId ??
        bookingById[bill.bookingId]?.branchId;
    final scoped = bills.where((bill) {
      return branchId == null ||
          branchId.isEmpty ||
          billBranch(bill) == branchId;
    }).toList();
    final paid = scoped.where((bill) => bill.isPaid).toList()
      ..sort((a, b) => b.revenueDate.compareTo(a.revenueDate));
    final pending = scoped.where((bill) => !bill.isPaid).toList();
    final dayStart = DateTime(now.year, now.month, now.day);
    final tomorrow = dayStart.add(const Duration(days: 1));
    final weekStart = dayStart.subtract(Duration(days: now.weekday - 1));
    final nextWeek = weekStart.add(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final yearStart = DateTime(now.year);
    final nextYear = DateTime(now.year + 1);

    double totalIn(DateTime start, DateTime end) => paid
        .where((bill) =>
            !bill.revenueDate.isBefore(start) && bill.revenueDate.isBefore(end))
        .fold(0, (sum, bill) => sum + bill.amount);
    int countIn(DateTime start, DateTime end) => paid
        .where((bill) =>
            !bill.revenueDate.isBefore(start) && bill.revenueDate.isBefore(end))
        .length;

    final allTime = paid.fold<double>(0, (sum, bill) => sum + bill.amount);
    final today = totalIn(dayStart, tomorrow);
    final week = totalIn(weekStart, nextWeek);
    final month = totalIn(monthStart, nextMonth);
    final year = totalIn(yearStart, nextYear);

    List<RevenueBreakdown> breakdown(
      String Function(Bill bill) id,
      String Function(Bill bill) label,
    ) {
      final totals = <String, double>{};
      final counts = <String, int>{};
      final labels = <String, String>{};
      for (final bill in paid) {
        final key = id(bill);
        totals[key] = (totals[key] ?? 0) + bill.amount;
        counts[key] = (counts[key] ?? 0) + 1;
        labels[key] = label(bill);
      }
      final result = totals.entries
          .map((entry) => RevenueBreakdown(
                id: entry.key,
                label: labels[entry.key] ?? entry.key,
                amount: entry.value,
                billCount: counts[entry.key] ?? 0,
                share: allTime == 0 ? 0 : entry.value / allTime,
              ))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      return result;
    }

    final dailyTrend = <RevenuePoint>[];
    for (var offset = 6; offset >= 0; offset--) {
      final start = dayStart.subtract(Duration(days: offset));
      dailyTrend.add(RevenuePoint(
        label: _weekdayLabel(start.weekday),
        amount: totalIn(start, start.add(const Duration(days: 1))),
      ));
    }
    final monthlyTrend = <RevenuePoint>[];
    for (var offset = 11; offset >= 0; offset--) {
      final start = DateTime(now.year, now.month - offset);
      monthlyTrend.add(RevenuePoint(
        label: _monthLabel(start.month),
        amount: totalIn(start, DateTime(start.year, start.month + 1)),
      ));
    }

    return RevenueAnalytics(
      today: today,
      week: week,
      month: month,
      year: year,
      allTime: allTime,
      paidBillCount: paid.length,
      pendingAmount: pending.fold(0, (sum, bill) => sum + bill.amount),
      pendingBillCount: pending.length,
      dailyTrend: dailyTrend,
      monthlyTrend: monthlyTrend,
      branchRevenue: breakdown(
        (bill) => billBranch(bill) ?? 'unassigned',
        (bill) {
          final id = billBranch(bill);
          return branchById[id]?.name ??
              bookingById[bill.bookingId]?.branchName ??
              'Unassigned branch';
        },
      ),
      technicianRevenue: breakdown(
        (bill) => bill.technicianId,
        (bill) =>
            technicianById[bill.technicianId]?.name ??
            'Technician ${bill.technicianId}',
      ),
      serviceRevenue: breakdown(
        (bill) => bookingById[bill.bookingId]?.applianceType ?? 'unknown',
        (bill) =>
            bookingById[bill.bookingId]?.applianceType ?? 'Unknown service',
      ),
      reportRows: [
        RevenueReportRow(
          period: 'Today',
          revenue: today,
          paidBills: countIn(dayStart, tomorrow),
        ),
        RevenueReportRow(
          period: 'This week',
          revenue: week,
          paidBills: countIn(weekStart, nextWeek),
        ),
        RevenueReportRow(
          period: 'This month',
          revenue: month,
          paidBills: countIn(monthStart, nextMonth),
        ),
        RevenueReportRow(
          period: 'This year',
          revenue: year,
          paidBills: countIn(yearStart, nextYear),
        ),
        RevenueReportRow(
          period: 'All time',
          revenue: allTime,
          paidBills: paid.length,
        ),
      ],
      recentPaidBills: paid.take(20).toList(),
    );
  }
}

class RevenuePoint {
  const RevenuePoint({required this.label, required this.amount});
  final String label;
  final double amount;
}

class RevenueBreakdown {
  const RevenueBreakdown({
    required this.id,
    required this.label,
    required this.amount,
    required this.billCount,
    required this.share,
  });
  final String id;
  final String label;
  final double amount;
  final int billCount;
  final double share;
}

class RevenueReportRow {
  const RevenueReportRow({
    required this.period,
    required this.revenue,
    required this.paidBills,
  });
  final String period;
  final double revenue;
  final int paidBills;
  double get averageBill => paidBills == 0 ? 0 : revenue / paidBills;
}

String _weekdayLabel(int weekday) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

String _monthLabel(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
