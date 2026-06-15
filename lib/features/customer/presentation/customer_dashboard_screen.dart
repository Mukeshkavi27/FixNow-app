import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../services/data/service_catalog_repository.dart';
import 'customer_providers.dart';

export 'customer_providers.dart';

final _selectedLocationProvider =
    StateProvider.autoDispose<String?>((ref) => null);

class CustomerDashboardScreen extends ConsumerWidget {
  const CustomerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final services = ref.watch(serviceCatalogProvider);
    final bookings = ref.watch(customerBookingsProvider);
    final location = ref.watch(_selectedLocationProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pagePadding = width >= 900 ? 28.0 : 16.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(serviceCatalogProvider);
                ref.invalidate(customerBookingsProvider);
                ref.invalidate(currentUserProvider);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(pagePadding, 12, pagePadding, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CustomerHeader(
                            userName: user.valueOrNull?.name ?? 'Customer',
                            profilePhoto: user.valueOrNull?.profilePhoto,
                            location: location,
                            onLocationTap: () =>
                                _showLocationSheet(context, ref),
                            onHistoryTap: () =>
                                context.push('/customer/history'),
                            onProfileTap: () =>
                                context.push('/customer/profile'),
                          ),
                          const SizedBox(height: 22),
                          const _WelcomeHero(),
                          const SizedBox(height: 18),
                          _SearchBar(
                            onTap: () => showSearch<String>(
                              context: context,
                              delegate: _ServiceSearchDelegate(
                                services.valueOrNull ??
                                    AppConstants.applianceCategories,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _SectionHeader(
                            title: 'Appliance services',
                            subtitle: 'Choose what needs attention today',
                            action: TextButton(
                              onPressed: () => showSearch<String>(
                                context: context,
                                delegate: _ServiceSearchDelegate(
                                  services.valueOrNull ??
                                      AppConstants.applianceCategories,
                                ),
                              ),
                              child: const Text('Search'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          services.when(
                            data: (items) => _ServiceGrid(services: items),
                            loading: () => const _ServiceGridSkeleton(),
                            error: (error, _) => _InlineError(
                              message: 'Services could not be loaded.',
                              onRetry: () =>
                                  ref.invalidate(serviceCatalogProvider),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _SectionHeader(
                            title: 'Your current service',
                            subtitle: 'Updates from booking to completion',
                            action: TextButton(
                              onPressed: () =>
                                  context.push('/customer/history'),
                              child: const Text('View all'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          bookings.when(
                            data: (items) {
                              final active = items
                                  .where((item) =>
                                      item.status != BookingStatus.closed)
                                  .toList();
                              if (active.isEmpty) {
                                return const _EmptyBookingCard();
                              }
                              return _ActiveBookingCard(booking: active.first);
                            },
                            loading: () => const _BookingSkeleton(),
                            error: (error, _) => _InlineError(
                              message: 'Bookings could not be loaded.',
                              onRetry: () =>
                                  ref.invalidate(customerBookingsProvider),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _PopularServices(
                            onBook: (service) => context.push(
                              '/book/${Uri.encodeComponent(service)}',
                            ),
                          ),
                          const SizedBox(height: 26),
                          _SupportBanner(
                            onTap: () async {
                              final number = AppConstants.whatsappSupportNumber
                                  .replaceAll('+', '');
                              await launchUrl(
                                Uri.parse(
                                  'https://wa.me/$number?text=Hello%20FixNow,%20I%20need%20help%20with%20a%20service.',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLocationSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LocationSheet(
        onSelected: (label) {
          ref.read(_selectedLocationProvider.notifier).state = label;
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.userName,
    required this.profilePhoto,
    required this.location,
    required this.onLocationTap,
    required this.onHistoryTap,
    required this.onProfileTap,
  });

  final String userName;
  final String? profilePhoto;
  final String? location;
  final VoidCallback onLocationTap;
  final VoidCallback onHistoryTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/images/fixnow_logo.png',
            width: 46,
            height: 46,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: InkWell(
            onTap: onLocationTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${userName.split(' ').first}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppTheme.badgeOrange,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          location ?? 'Choose service location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _HeaderIconButton(
          tooltip: 'Bookings and bills',
          icon: Icons.shopping_bag_outlined,
          onTap: onHistoryTap,
        ),
        const SizedBox(width: 7),
        Semantics(
          button: true,
          label: 'Open profile',
          child: InkWell(
            onTap: onProfileTap,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 21,
              backgroundColor: AppTheme.primary,
              foregroundImage: profilePhoto == null || profilePhoto!.isEmpty
                  ? null
                  : NetworkImage(profilePhoto!),
              child: profilePhoto == null || profilePhoto!.isEmpty
                  ? Text(
                      _initials(userName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size(42, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.divider),
        ),
      ),
      icon: Icon(icon, color: AppTheme.textPrimary, size: 21),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reliable home care,\nright when you need it',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Verified technicians, clear estimates and live updates.',
                  style: TextStyle(
                    color: Color(0xFFD8DEE6),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.home_repair_service_outlined,
              color: Colors.white,
              size: 42,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: AppTheme.textHint, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search AC repair, cleaning, purifier service...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        action,
      ],
    );
  }
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.services});

  final List<ApplianceCategory> services;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 600
                ? 4
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: services.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 1.2 : 1.15,
          ),
          itemBuilder: (context, index) {
            final service = services[index];
            return _ServiceCard(
              service: service,
              onTap: () => context.push(
                '/book/${Uri.encodeComponent(service.name)}',
              ),
            );
          },
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final ApplianceCategory service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _serviceColor(service.name);
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: service.imageUrl == null
                    ? Icon(_serviceIcon(service.name), color: color, size: 23)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          service.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            _serviceIcon(service.name),
                            color: color,
                          ),
                        ),
                      ),
              ),
              const Spacer(),
              Text(
                service.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                service.startingPrice,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBookingCard extends StatelessWidget {
  const _ActiveBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final progress = (booking.status.index + 1) / BookingStatus.values.length;
    return InkWell(
      onTap: () => context.push('/booking/${booking.id}'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _serviceIcon(booking.applianceType),
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
                      const SizedBox(height: 3),
                      Text(
                        booking.technicianName == null
                            ? 'Technician assignment in progress'
                            : 'Technician: ${booking.technicianName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textHint),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  booking.status.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  booking.preferredTime,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: AppTheme.accent,
                backgroundColor: AppTheme.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBookingCard extends StatelessWidget {
  const _EmptyBookingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Row(
        children: [
          Icon(Icons.event_available_outlined, color: AppTheme.accent),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No active booking. Choose an appliance above when you need us.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularServices extends StatelessWidget {
  const _PopularServices({required this.onBook});

  final ValueChanged<String> onBook;

  static const items = [
    ('AC Repair', 'Rs. 499', Icons.ac_unit, Color(0xFFE8F4FD)),
    (
      'Washing Machine',
      'Rs. 449',
      Icons.local_laundry_service,
      Color(0xFFEAF7EF)
    ),
    ('Water Purifier', 'Rs. 349', Icons.water_drop_outlined, Color(0xFFFFF1E7)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Popular this week',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 174,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 184,
                child: InkWell(
                  onTap: () => onBook(item.$1),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: item.$4,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$3, color: AppTheme.primary, size: 30),
                        const Spacer(),
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Starting ${item.$2}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            Icon(Icons.star,
                                size: 14, color: AppTheme.starColor),
                            SizedBox(width: 4),
                            Text(
                              '4.8',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SupportBanner extends StatelessWidget {
  const _SupportBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7EF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.support_agent, color: Color(0xFF16845B), size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help choosing a service?',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Chat with FixNow support on WhatsApp.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: Color(0xFF16845B)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final controller = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> detect() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission is required.');
      }
      final position = await Geolocator.getCurrentPosition();
      widget.onSelected(
        '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not access location. Enter your area manually.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Service location',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'This helps us show technicians available near you.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Area, street or landmark',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                widget.onSelected(value.trim());
              }
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : detect,
            icon: loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(loading ? 'Detecting...' : 'Use current location'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) widget.onSelected(value);
            },
            child: const Text('Confirm location'),
          ),
        ],
      ),
    );
  }
}

class _ServiceSearchDelegate extends SearchDelegate<String> {
  _ServiceSearchDelegate(this.services);

  final List<ApplianceCategory> services;

  @override
  String get searchFieldLabel => 'Search services';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            onPressed: () => query = '',
            icon: const Icon(Icons.close),
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        onPressed: () => close(context, ''),
        icon: const Icon(Icons.arrow_back),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final filtered = services
        .where(
          (service) =>
              query.isEmpty ||
              service.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('No matching service found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final service = filtered[index];
        return ListTile(
          leading: Icon(_serviceIcon(service.name)),
          title: Text(service.name),
          subtitle: Text(service.startingPrice),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            close(context, service.name);
            context.push('/book/${Uri.encodeComponent(service.name)}');
          },
        );
      },
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ServiceGridSkeleton extends StatelessWidget {
  const _ServiceGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.2,
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _BookingSkeleton extends StatelessWidget {
  const _BookingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

IconData _serviceIcon(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('air conditioner') || normalized.contains('ac ')) {
    return Icons.ac_unit;
  }
  if (normalized.contains('refrigerator')) return Icons.kitchen_outlined;
  if (normalized.contains('washing')) return Icons.local_laundry_service;
  if (normalized.contains('microwave')) return Icons.microwave_outlined;
  if (normalized.contains('purifier')) return Icons.water_drop_outlined;
  if (normalized.contains('television')) return Icons.tv_outlined;
  if (normalized.contains('fan')) return Icons.air;
  return Icons.home_repair_service_outlined;
}

Color _serviceColor(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('air') || normalized.contains('ac')) {
    return const Color(0xFF2F80ED);
  }
  if (normalized.contains('washing')) return const Color(0xFF16845B);
  if (normalized.contains('purifier')) return const Color(0xFF00A6A6);
  if (normalized.contains('refrigerator')) return const Color(0xFF6C5CE7);
  if (normalized.contains('television')) return const Color(0xFF444B59);
  if (normalized.contains('fan')) return const Color(0xFFE67E22);
  return AppTheme.primary;
}
