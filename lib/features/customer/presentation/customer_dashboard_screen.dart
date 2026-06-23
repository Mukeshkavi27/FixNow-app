import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/resilient_asset_image.dart';
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
    final isWide = width >= 900;
    final showDesktopSupportPrompt = width >= 1280;
    Future<void> openSupport() async {
      final number = AppConstants.whatsappSupportNumber.replaceAll('+', '');
      await launchUrl(
        Uri.parse(
          'https://wa.me/$number?text=Hello%20FixNow,%20I%20need%20help%20with%20a%20service.',
        ),
        mode: LaunchMode.externalApplication,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
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
                          padding: EdgeInsets.fromLTRB(
                            pagePadding,
                            12,
                            pagePadding,
                            isWide ? 32 : 96,
                          ),
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
                                  return _ActiveBookingCard(
                                    booking: active.first,
                                  );
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
                                services: services.valueOrNull ??
                                    AppConstants.applianceCategories,
                                onBook: (service) => context.push(
                                  '/book/${Uri.encodeComponent(service)}',
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
            ),
            Positioned(
              right: showDesktopSupportPrompt ? 20 : 16,
              bottom: showDesktopSupportPrompt ? 24 : 18,
              top: null,
              child: _SupportChatLauncher(
                expanded: showDesktopSupportPrompt,
                onTap: openSupport,
              ),
            ),
          ],
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
          child: const ResilientAssetImage(
            assetName: 'assets/images/fixnow_logo.png',
            width: 46,
            height: 46,
            fit: BoxFit.contain,
            fallbackIcon: Icons.home_repair_service_outlined,
            fallbackIconSize: 20,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Positioned.fill(
            child: const ResilientAssetImage(
              assetName: 'assets/images/fix_now_general.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              fallbackIcon: Icons.handyman_outlined,
              fallbackIconSize: 60,
              fallbackBackgroundColor: Color(0xFFEAF1FF),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.9),
                    AppTheme.primary.withValues(alpha: 0.62),
                    AppTheme.accent.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
              ),
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
                          color: Color(0xFFF4F8FF),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: const ResilientAssetImage(
                          assetName: 'assets/images/fixnow_logo.png',
                          fit: BoxFit.contain,
                          fallbackIcon: Icons.home_repair_service_outlined,
                          fallbackIconSize: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
            childAspectRatio: columns == 2 ? 0.82 : 0.86,
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image fills the full width of the card, across the top.
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: color.withValues(alpha: 0.09),
                  child: _ServiceCardImage(service: service, color: color),
                ),
              ),
              // Name and price sit in their own section below the image.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolves which image to show, in this order:
/// 1. A bundled local asset (e.g. 'assets/images/television.png'). This is
///    what the hardcoded AppConstants.applianceCategories list uses.
/// 2. A remote network image, used for Firestore-sourced or user-uploaded
///    photos (e.g. an appliance category image, or a customer's own photo
///    of their broken appliance taken at booking time).
/// 3. A Material icon fallback, used if neither is available, or if the
///    asset/network image fails to load (e.g. a typo'd or missing file).
///
/// This is shared by the big service-grid cards and by the smaller image
/// chips (active booking card, popular-services card) so every appliance
/// image on the dashboard resolves the same way.
class _ResilientImage extends StatelessWidget {
  const _ResilientImage({
    required this.fallbackIcon,
    required this.color,
    this.assetName,
    this.imageUrl,
    this.iconSize = 20,
  });

  final String? assetName;
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color color;
  final double iconSize;

  bool get _hasLocalAsset =>
      assetName != null &&
      assetName!.startsWith('assets/') &&
      assetName!.toLowerCase().endsWith('.png');

  @override
  Widget build(BuildContext context) {
    if (_hasLocalAsset) {
      return Image.asset(
        assetName!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Center(child: Icon(fallbackIcon, color: color, size: iconSize));
  }
}

class _ServiceCardImage extends StatelessWidget {
  const _ServiceCardImage({required this.service, required this.color});

  final ApplianceCategory service;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _ResilientImage(
      assetName: service.assetName,
      imageUrl: service.imageUrl,
      fallbackIcon: _serviceIcon(service.name),
      color: color,
      iconSize: 36,
    );
  }
}

class _ActiveBookingCard extends StatelessWidget {
  const _ActiveBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final progress = (booking.status.index + 1) / BookingStatus.values.length;
    final assetName = _serviceAssetName(booking.applianceType);
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _ResilientImage(
                      assetName: assetName,
                      imageUrl: booking.imageUrl,
                      fallbackIcon: _serviceIcon(booking.applianceType),
                      color: AppTheme.primary,
                      iconSize: 22,
                    ),
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
  const _PopularServices({required this.services, required this.onBook});

  final List<ApplianceCategory> services;
  final ValueChanged<String> onBook;

  // label, price, fallback icon, background color, keyword to match
  // against the real service catalog so the same image used in the
  // grid above shows up here too.
  static const items = [
    ('AC Repair', 'Rs. 499', Icons.ac_unit, Color(0xFFE8F4FD), 'air'),
    (
      'Washing Machine',
      'Rs. 449',
      Icons.local_laundry_service,
      Color(0xFFEAF7EF),
      'washing',
    ),
    (
      'Water Purifier',
      'Rs. 349',
      Icons.water_drop_outlined,
      Color(0xFFFFF1E7),
      'purifier',
    ),
  ];

  ApplianceCategory? _match(String keyword) {
    for (final service in services) {
      if (service.name.toLowerCase().contains(keyword)) return service;
    }
    return null;
  }

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
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final matched = _match(item.$5);
              return SizedBox(
                width: 218,
                child: InkWell(
                  onTap: () => onBook(item.$1),
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: _ResilientImage(
                              assetName: matched?.assetName,
                              imageUrl: matched?.imageUrl,
                              fallbackIcon: item.$3,
                              color: AppTheme.primary,
                              iconSize: 22,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                                  Icon(
                                    Icons.star,
                                    size: 14,
                                    color: AppTheme.starColor,
                                  ),
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

class _SupportChatLauncher extends StatelessWidget {
  const _SupportChatLauncher({
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return SizedBox(
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Not able to identify the right service?',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Ask our experts.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SupportActionButton(
              expanded: false,
              onTap: onTap,
            ),
          ],
        ),
      );
    }

    if (expanded) {
      return SizedBox(
        width: 320,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.divider),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Not able to identify the right service?',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Ask our experts on WhatsApp.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _SupportActionButton(
              expanded: true,
              onTap: onTap,
            ),
          ],
        ),
      );
    }

    return _SupportActionButton(
      expanded: false,
      onTap: onTap,
    );
  }
}

class _SupportActionButton extends StatelessWidget {
  const _SupportActionButton({
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 10,
      shadowColor: AppTheme.primary.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: expanded ? 88 : 64,
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F8F61),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F8F61).withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: expanded
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SupportIconBadge(),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                  ],
                )
              : const Center(
                  child: _SupportIconBadge(compact: true),
                ),
        ),
      ),
    );
  }
}

class _SupportIconBadge extends StatelessWidget {
  const _SupportIconBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 42 : 40,
      height: compact ? 42 : 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Icon(
        Icons.support_agent,
        color: Colors.white,
        size: 25,
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

String? _serviceAssetName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('air conditioner') ||
      normalized == 'ac' ||
      normalized.contains('ac repair')) {
    return 'assets/images/ac.png';
  }
  if (normalized.contains('refrigerator') || normalized.contains('fridge')) {
    return 'assets/images/refrigerator.png';
  }
  if (normalized.contains('washing')) {
    return 'assets/images/washing_machine.png';
  }
  if (normalized.contains('microwave')) {
    return 'assets/images/microwave.png';
  }
  if (normalized.contains('purifier')) {
    return 'assets/images/water_purifier.png';
  }
  if (normalized.contains('television') || normalized.contains('tv')) {
    return 'assets/images/television.png';
  }
  if (normalized.contains('fan')) return 'assets/images/fan.png';
  if (normalized.contains('other')) return 'assets/images/other_services.png';
  return null;
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
