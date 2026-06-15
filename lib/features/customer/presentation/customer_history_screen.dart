import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/booking_status.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/domain/bill.dart';
import 'customer_providers.dart';

class CustomerHistoryScreen extends ConsumerWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(customerBookingsProvider);
    final bills = ref.watch(customerBillsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bookings and bills'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'History'),
              Tab(text: 'Bills'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            bookings.when(
              data: (items) => _BookingList(
                bookings: items
                    .where((item) => item.status != BookingStatus.closed)
                    .toList(),
                emptyTitle: 'No active bookings',
                emptyMessage:
                    'Your upcoming and in-progress services will appear here.',
              ),
              loading: _loading,
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(customerBookingsProvider),
              ),
            ),
            bookings.when(
              data: (items) => _BookingList(
                bookings: items
                    .where((item) => item.status == BookingStatus.closed)
                    .toList(),
                emptyTitle: 'No completed services yet',
                emptyMessage:
                    'Completed service history will be available here.',
              ),
              loading: _loading,
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(customerBookingsProvider),
              ),
            ),
            bills.when(
              data: (items) => _BillList(bills: items),
              loading: _loading,
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(customerBillsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _loading() => const Center(child: CircularProgressIndicator());
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Booking> bookings;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return _EmptyState(
        icon: Icons.home_repair_service_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return InkWell(
          onTap: () => context.push('/booking/${booking.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.home_repair_service_outlined,
                    color: AppTheme.primary,
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
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMM yyyy').format(booking.preferredDate),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _StatusPill(status: booking.status),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textHint),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final color =
        status == BookingStatus.closed ? AppTheme.accentDark : AppTheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BillList extends StatelessWidget {
  const _BillList({required this.bills});

  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No bills generated',
        message: 'Final service bills will be stored here for easy access.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final bill = bills[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill ${bill.bookingId.length > 8 ? bill.bookingId.substring(0, 8) : bill.bookingId}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy').format(bill.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${bill.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bill.isPaid ? 'Paid' : 'Payment pending',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: bill.isPaid ? AppTheme.accentDark : Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load this information.'),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
