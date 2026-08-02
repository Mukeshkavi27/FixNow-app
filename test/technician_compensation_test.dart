import 'package:fixnow/features/shared/domain/bill.dart';
import 'package:fixnow/features/shared/domain/technician_compensation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic incentive starts separately at 8000 daily collection', () {
    expect(automaticDailyIncentive(7999), 0);
    expect(automaticDailyIncentive(8000), 100);
    expect(automaticDailyIncentive(10000), 300);
  });

  test('automatic incentive aggregates each collection day separately', () {
    final bills = [
      Bill(
        id: 'one',
        bookingId: 'one',
        customerId: 'customer',
        technicianId: 'tech',
        amount: 8000,
        createdAt: DateTime(2026, 7, 2),
        paidAt: DateTime(2026, 7, 2),
        isPaid: true,
      ),
      Bill(
        id: 'two',
        bookingId: 'two',
        customerId: 'customer',
        technicianId: 'tech',
        amount: 10000,
        createdAt: DateTime(2026, 7, 3),
        paidAt: DateTime(2026, 7, 3),
        isPaid: true,
      ),
    ];

    expect(
      automaticIncentiveForPeriod(
        bills: bills,
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
      ),
      400,
    );
  });
}
