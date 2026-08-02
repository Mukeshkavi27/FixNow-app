import 'bill.dart';

double automaticDailyIncentive(double collection) {
  if (collection >= 20000) {
    return 1000 + ((collection - 20000) / 1000).floor() * 100;
  }
  if (collection >= 17500) return 750;
  if (collection >= 15000) return 500;
  if (collection >= 12500) return 400;
  if (collection >= 10000) return 300;
  if (collection >= 9000) return 200;
  if (collection >= 8000) return 100;
  return 0;
}

double proratedDailySalary(double monthlySalary, DateTime date) {
  if (monthlySalary <= 0) return 0;
  final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
  return monthlySalary / daysInMonth;
}

double automaticIncentiveForPeriod({
  required Iterable<Bill> bills,
  required DateTime start,
  required DateTime end,
}) {
  final dailyCollections = <DateTime, double>{};
  for (final bill in bills.where((bill) => bill.isPaid)) {
    final date = bill.revenueDate;
    if (date.isBefore(start) || !date.isBefore(end)) continue;
    final day = DateTime(date.year, date.month, date.day);
    dailyCollections[day] = (dailyCollections[day] ?? 0) + bill.amount;
  }
  return dailyCollections.values.fold<double>(
    0,
    (sum, collection) => sum + automaticDailyIncentive(collection),
  );
}
