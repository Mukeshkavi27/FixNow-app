import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';

final customerBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchCustomerBookings(user.uid);
});

// Category filter state
final _selectedCategoryProvider = StateProvider.autoDispose<String?>((ref) => null);

class CustomerDashboardScreen extends ConsumerWidget {
  const CustomerDashboardScreen({super.key});

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/${AppConstants.whatsappSupportNumber.replaceAll('+', '')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(customerBookingsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final selectedCategory = ref.watch(_selectedCategoryProvider);
    final cs = Theme.of(context).colorScheme;

    final categories = AppConstants.applianceCategories;
    final filtered = selectedCategory == null
        ? categories
        : categories.where((c) => c.name == selectedCategory).toList();

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${user?.name.split(' ').first ?? 'there'} 👋',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  'What needs fixing today?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'WhatsApp support',
                onPressed: _openWhatsapp,
                icon: Icon(Icons.support_agent_outlined, color: cs.primary),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                icon: Icon(Icons.logout, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ── Search bar ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Search for a service…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Promo banner ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      top: -10,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'LIMITED OFFER',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Flat 20% off on first booking',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            'Use code FIXNOW20',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Section title ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Our Services',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${categories.length} services',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // ── Category filter chips ─────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: selectedCategory == null,
                    onTap: () =>
                        ref.read(_selectedCategoryProvider.notifier).state = null,
                  ),
                  const SizedBox(width: 8),
                  ...categories.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: c.name,
                        selected: selectedCategory == c.name,
                        onTap: () => ref
                            .read(_selectedCategoryProvider.notifier)
                            .state = c.name,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Service cards grid ────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final category = filtered[index];
                  return _ServiceCard(category: category);
                },
                childCount: filtered.length,
              ),
            ),
          ),

          // ── My Bookings ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
              child: Text(
                'My Bookings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: bookings.when(
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 40, color: cs.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            'No bookings yet',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: items.map((b) => _BookingTile(booking: b)).toList(),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(e.toString()),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.category});
  final ApplianceCategory category;

  @override
  Widget build(BuildContext context, ) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => context.push('/book/${Uri.encodeComponent(category.name)}'),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image block ─ drop your asset here
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Replace this Container with Image.asset(category.assetName) ──
                    Container(
                      color: cs.primaryContainer,
                      child: Icon(
                        _iconFor(category.name),
                        size: 52,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    // Discount badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '20% OFF',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                    // Rating badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 11, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              '4.8',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Info block
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.startingPrice,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => context
                          .push('/book/${Uri.encodeComponent(category.name)}'),
                      child: const Text('Book Now'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withOpacity(0.4),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

// ── Booking tile ──────────────────────────────────────────────────────────────

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color statusColor() {
      final s = booking.status.name;
      if (s == 'closed') return Colors.green;
      if (s.contains('service') || s.contains('bill')) return cs.primary;
      if (s == 'booked') return Colors.orange;
      return cs.tertiary;
    }

    return GestureDetector(
      onTap: () => context.push('/booking/${booking.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.home_repair_service_outlined,
                color: cs.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.applianceType,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    booking.preferredTime,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor().withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                booking.status.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor(),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}