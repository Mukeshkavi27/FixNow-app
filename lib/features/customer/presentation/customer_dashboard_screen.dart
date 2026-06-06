import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/widgets/app_scaffold.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';

final customerBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchCustomerBookings(user.uid);
});

class CustomerDashboardScreen extends ConsumerWidget {
  const CustomerDashboardScreen({super.key});

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse('https://wa.me/${AppConstants.whatsappSupportNumber.replaceAll('+', '')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(customerBookingsProvider);
    return AppScaffold(
      title: 'Customer Dashboard',
      actions: [
        IconButton(
          tooltip: 'WhatsApp support',
          onPressed: _openWhatsapp,
          icon: const Icon(Icons.support_agent),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Book a Service', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width > 900 ? 4 : width > 560 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: AppConstants.applianceCategories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: width > 560 ? 1.05 : .86,
                ),
                itemBuilder: (context, index) {
                  final category = AppConstants.applianceCategories[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _iconFor(category.name),
                                size: 48,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(category.startingPrice, style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () => context.push('/book/${Uri.encodeComponent(category.name)}'),
                            child: const Text('Book Service'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Text('My Bookings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          bookings.when(
            data: (items) => items.isEmpty
                ? const ListTile(title: Text('No bookings yet'))
                : Column(
                    children: items
                        .map(
                          (booking) => Card(
                            child: ListTile(
                              title: Text(booking.applianceType),
                              subtitle: Text('${booking.status.label} • ${booking.preferredTime}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/booking/${booking.id}'),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String name) {
    return switch (name) {
      'Air Conditioner' => Icons.ac_unit,
      'Refrigerator' => Icons.kitchen,
      'Washing Machine' => Icons.local_laundry_service,
      'Microwave' => Icons.microwave,
      'Water Purifier' => Icons.water_drop,
      'Television' => Icons.tv,
      'Fan' => Icons.air,
      _ => Icons.home_repair_service,
    };
  }
}
