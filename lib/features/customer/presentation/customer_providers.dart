import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/domain/bill.dart';

final customerBookingsProvider =
    StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchCustomerBookings(user.uid);
});

final customerBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Bill>[]);
  return ref.watch(billRepositoryProvider).watchCustomerBills(user.uid);
});
