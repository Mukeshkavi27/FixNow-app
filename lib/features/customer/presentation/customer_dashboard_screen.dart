import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../services/data/service_catalog_repository.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/domain/bill.dart';

final customerBookingsProvider =
    StreamProvider.autoDispose<List<Booking>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Booking>[]);
  return ref.watch(bookingRepositoryProvider).watchCustomerBookings(user.uid);
});

final customerBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(<Bill>[]);
  return ref.watch(billRepositoryProvider).watchCustomerBills(user.uid);
});

final _selectedCategoryProvider =
    StateProvider.autoDispose<String?>((ref) => null);
final _bottomNavIndexProvider = StateProvider.autoDispose<int>((ref) => 0);

/// Holds the currently selected address label shown in the top bar
final _selectedLocationProvider =
    StateProvider.autoDispose<String?>((ref) => null);

// Most booked services data
const _mostBooked = [
  _MostBookedItem(
    label: 'Bathroom Cleaning',
    price: 'â‚¹979',
    originalPrice: 'â‚¹1,058',
    rating: 4.80,
    imagePlaceholderColor: Color(0xFFE8F4FD),
    iconData: Icons.bathtub_outlined,
  ),
  _MostBookedItem(
    label: 'AC Repair',
    price: 'â‚¹299',
    originalPrice: null,
    rating: 4.73,
    isInstant: true,
    imagePlaceholderColor: Color(0xFFE8F8F0),
    iconData: Icons.ac_unit,
  ),
  _MostBookedItem(
    label: 'Foam-jet AC Service',
    price: 'â‚¹999',
    originalPrice: null,
    rating: 4.76,
    isInstant: true,
    imagePlaceholderColor: Color(0xFFFFF3E8),
    iconData: Icons.air,
  ),
  _MostBookedItem(
    label: 'Kitchen Cleaning',
    price: 'â‚¹1,429',
    originalPrice: 'â‚¹1,587',
    rating: 4.80,
    imagePlaceholderColor: Color(0xFFFFF0F0),
    iconData: Icons.kitchen,
  ),
  _MostBookedItem(
    label: 'Fan Repair',
    price: 'â‚¹109',
    originalPrice: null,
    rating: 4.80,
    imagePlaceholderColor: Color(0xFFF0F0FF),
    iconData: Icons.air,
  ),
];

// â”€â”€ Location picker bottom sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _LocationPickerSheet extends ConsumerStatefulWidget {
  const _LocationPickerSheet();

  @override
  ConsumerState<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  bool _detecting = false;
  String? _error;
  final _searchController = TextEditingController();

  final List<Map<String, dynamic>> _savedAddresses = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _detecting = true;
      _error = null;
    });

    try {
      // 1. Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = 'Location services are disabled. Please enable GPS.';
          _detecting = false;
        });
        return;
      }

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _error = 'Location permission denied.';
            _detecting = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error =
              'Location permission permanently denied. Enable it in Settings.';
          _detecting = false;
        });
        return;
      }

      // 3. Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // 4. Reverse geocode via OpenStreetMap Nominatim (works on web + mobile)
      final lat = position.latitude;
      final lon = position.longitude;
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon'
        '&format=json&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'Accept-Language': 'en', 'User-Agent': 'FixNowApp/1.0'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final parts = <String>[
          if (addr['neighbourhood'] != null) addr['neighbourhood'] as String,
          if (addr['suburb'] != null) addr['suburb'] as String,
          if (addr['city'] != null)
            addr['city'] as String
          else if (addr['town'] != null)
            addr['town'] as String
          else if (addr['village'] != null)
            addr['village'] as String,
        ];
        final address = parts.isNotEmpty
            ? parts.join(', ')
            : (data['display_name'] as String? ?? 'Current location');

        if (!mounted) return;
        ref.read(_selectedLocationProvider.notifier).state = address;
        Navigator.of(context).pop();
      } else {
        throw Exception('Geocoding failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not detect location. Try again.';
        _detecting = false;
      });
    }
  }

  void _selectAddress(String address) {
    ref.read(_selectedLocationProvider.notifier).state = address;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select your location',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Search bar (manual address search)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search area, street nameâ€¦',
                hintStyle: const TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppTheme.textHint,
                ),
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Use current location button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: _detecting ? null : _detectLocation,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _detecting
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _detecting
                              ? 'Detecting locationâ€¦'
                              : 'Use current location',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Text(
                          'Using GPS',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textHint),
                  ],
                ),
              ),
            ),
          ),

          // Error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Saved addresses
          if (_savedAddresses.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                'Saved addresses',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ..._savedAddresses.map(
              (addr) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: InkWell(
                  onTap: () => _selectAddress(addr['address'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            addr['icon'] as IconData,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                addr['label'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                addr['address'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: AppTheme.textHint),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// â”€â”€ Main dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class CustomerDashboardScreen extends ConsumerStatefulWidget {
  const CustomerDashboardScreen({super.key});

  @override
  ConsumerState<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState
    extends ConsumerState<CustomerDashboardScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/${AppConstants.whatsappSupportNumber.replaceAll('+', '')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LocationPickerSheet(),
    );
  }

  void _handleNavigation(int index) {
    ref.read(_bottomNavIndexProvider.notifier).state = index;
    final target = switch (index) {
      0 => 0.0,
      1 => _scrollController.position.maxScrollExtent,
      2 => (_scrollController.position.maxScrollExtent * 0.5),
      _ => null,
    };
    if (target != null) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ref.read(currentUserProvider).valueOrNull?.name ?? 'Customer',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(ref.read(currentUserProvider).valueOrNull?.email ?? ''),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(authRepositoryProvider).signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(customerBookingsProvider);
    final bills = ref.watch(customerBillsProvider);
    final catalog = ref.watch(serviceCatalogProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final navIndex = ref.watch(_bottomNavIndexProvider);
    final selectedCategory = ref.watch(_selectedCategoryProvider);
    final selectedLocation = ref.watch(_selectedLocationProvider);
    final categories = catalog.valueOrNull ?? AppConstants.applianceCategories;
    final filtered = selectedCategory == null
        ? categories
        : categories.where((c) => c.name == selectedCategory).toList();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final serviceColumnCount = switch (screenWidth) {
      >= 1180 => 5,
      >= 850 => 4,
      >= 600 => 3,
      _ => 2,
    };
    final horizontalPadding = isDesktop ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _UCBottomNav(
            index: navIndex,
            onTap: _handleNavigation,
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // â”€â”€ Sticky top bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverAppBar(
                pinned: true,
                floating: false,
                backgroundColor: AppTheme.background,
                elevation: 0,
                scrolledUnderElevation: 1,
                shadowColor: const Color(0x18000000),
                titleSpacing: 0,
                toolbarHeight: 60,
                title: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    children: [
                      // Logo
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'FN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // â”€â”€ Location pill (tappable) â”€â”€
                      Expanded(
                        child: GestureDetector(
                          onTap: _openLocationPicker,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selectedLocation != null
                                      ? Icons.location_on
                                      : Icons.location_on_outlined,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    selectedLocation ?? 'Select your location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: selectedLocation != null
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                      fontWeight: selectedLocation != null
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down,
                                    size: 16, color: AppTheme.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Cart
                      IconButton(
                        tooltip: 'My bookings',
                        onPressed: () => _handleNavigation(1),
                        icon: const Icon(Icons.receipt_long_outlined,
                            color: AppTheme.primary),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),

                      // Profile / sign out
                      IconButton(
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                        icon: const Icon(Icons.person_outline,
                            color: AppTheme.primary),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
              ),

              // â”€â”€ Hero section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverToBoxAdapter(
                child: _HeroSection(user: user, onWhatsapp: _openWhatsapp),
              ),

              // â”€â”€ Search bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    0,
                  ),
                  child: GestureDetector(
                    onTap: () => showSearch(
                      context: context,
                      delegate: _ServiceSearchDelegate(
                        categories: AppConstants.applianceCategories,
                      ),
                    ),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(Icons.search,
                              color: AppTheme.textHint, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Search for 'AC service'",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textHint,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // â”€â”€ Service categories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: horizontalPadding),
                  child: Text(
                    'What are you looking for?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 88,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final c = categories[i];
                      return _CategoryIconItem(category: c);
                    },
                  ),
                ),
              ),

              // â”€â”€ Most booked â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Most booked services',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {},
                        child: const Text(
                          'See all',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 214,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    itemCount: _mostBooked.length,
                    itemBuilder: (context, i) {
                      return _MostBookedCard(
                        item: _mostBooked[i],
                        onTap: () => context.push(
                          '/book/${Uri.encodeComponent(_mostBooked[i].label)}',
                        ),
                      );
                    },
                  ),
                ),
              ),

              // â”€â”€ All services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: const Text(
                    'All services',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    children: [
                      _UCFilterChip(
                        label: 'All',
                        selected: selectedCategory == null,
                        onTap: () => ref
                            .read(_selectedCategoryProvider.notifier)
                            .state = null,
                      ),
                      const SizedBox(width: 8),
                      ...categories.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _UCFilterChip(
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
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: serviceColumnCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: isDesktop ? 210 : 220,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ServiceGridCard(category: filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),

              // â”€â”€ My Bookings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'My bookings',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: bookings.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 40, color: AppTheme.textHint),
                              const SizedBox(height: 10),
                              const Text(
                                'No bookings yet',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Book a service to get started',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: Column(
                        children:
                            items.map((b) => _BookingTile(booking: b)).toList(),
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

              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: const Text(
                    'Bill history',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: bills.when(
                  data: (items) => Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: items.isEmpty
                        ? const Text(
                            'No bills generated yet.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          )
                        : Column(
                            children: items
                                .map(
                                  (bill) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.receipt_long_outlined,
                                      color: AppTheme.primary,
                                    ),
                                    title: Text(
                                      'INR ${bill.amount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      bill.isPaid ? 'Paid' : 'Payment due',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => context
                                        .push('/booking/${bill.bookingId}'),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Unable to load bills: $error'),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Hero section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.user, required this.onWhatsapp});
  final dynamic user;
  final VoidCallback onWhatsapp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Home services\nat your doorstep',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppTheme.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 14, color: AppTheme.starColor),
                SizedBox(width: 3),
                Text(
                  '4.8',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(width: 12),
                Icon(
                  Icons.people_outline,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: 3),
                Text(
                  '12M+',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3EB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD5B2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 14,
                    color: AppTheme.badgeOrange,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Flat 20% off on first booking',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.badgeOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final tiles = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _HeroImageTile(
              color: Color(0xFFE8EAF6),
              icon: Icons.build_outlined,
              label: 'Maintenance',
            ),
            _HeroImageTile(
              color: Color(0xFFE8F5E9),
              icon: Icons.cleaning_services_outlined,
              label: 'Cleaning',
            ),
            _HeroImageTile(
              color: Color(0xFFE3F2FD),
              icon: Icons.ac_unit,
              label: 'AC',
            ),
            _HeroImageTile(
              color: Color(0xFFFFF3E0),
              icon: Icons.electrical_services,
              label: 'Electric',
            ),
          ],
        );

        return Container(
          color: AppTheme.background,
          padding: EdgeInsets.fromLTRB(
            isWide ? 24 : 16,
            20,
            isWide ? 24 : 16,
            0,
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 32),
                    SizedBox(width: 312, child: tiles),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: 18),
                    tiles,
                  ],
                ),
        );
      },
    );
  }
}

class _HeroImageTile extends StatelessWidget {
  const _HeroImageTile(
      {required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 64,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: AppTheme.primary),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

// â”€â”€ Category icon item â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CategoryIconItem extends StatelessWidget {
  const _CategoryIconItem({required this.category});
  final ApplianceCategory category;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/${Uri.encodeComponent(category.name)}'),
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(
                _iconFor(category.name),
                size: 24,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) => switch (name) {
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

// â”€â”€ Most booked card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MostBookedItem {
  final String label;
  final String price;
  final String? originalPrice;
  final double rating;
  final bool isInstant;
  final Color imagePlaceholderColor;
  final IconData iconData;

  const _MostBookedItem({
    required this.label,
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.imagePlaceholderColor,
    required this.iconData,
    this.isInstant = false,
  });
}

class _MostBookedCard extends StatelessWidget {
  const _MostBookedCard({required this.item, required this.onTap});
  final _MostBookedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 142,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Container(
                height: 104,
                color: item.imagePlaceholderColor,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(item.iconData,
                          size: 42,
                          color: AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                    if (item.isInstant)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.instantGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.bolt, size: 10, color: Colors.white),
                              SizedBox(width: 2),
                              Text('Instant',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.3)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 11, color: AppTheme.starColor),
                      const SizedBox(width: 2),
                      Text(item.rating.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(item.price,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary)),
                      if (item.originalPrice != null) ...[
                        Text(item.originalPrice!,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textHint,
                                decoration: TextDecoration.lineThrough)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Service grid card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ServiceGridCard extends StatelessWidget {
  const _ServiceGridCard({required this.category});
  final ApplianceCategory category;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/book/${Uri.encodeComponent(category.name)}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 104,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: _bgFor(category.name),
                      child: Icon(
                        _iconFor(category.name),
                        size: 42,
                        color: AppTheme.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppTheme.badgeOrange,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('20% OFF',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.star,
                                size: 9, color: AppTheme.starColor),
                            SizedBox(width: 2),
                            Text('4.8',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(category.startingPrice,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
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

  Color _bgFor(String name) => switch (name) {
        'Air Conditioner' => const Color(0xFFE8F4FD),
        'Refrigerator' => const Color(0xFFE8F5E9),
        'Washing Machine' => const Color(0xFFE3F2FD),
        'Microwave' => const Color(0xFFFFF3E0),
        'Water Purifier' => const Color(0xFFE0F7FA),
        'Television' => const Color(0xFFF3E5F5),
        'Fan' => const Color(0xFFFFF8E1),
        _ => const Color(0xFFF5F5F5),
      };

  IconData _iconFor(String name) => switch (name) {
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

// â”€â”€ Filter chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _UCFilterChip extends StatelessWidget {
  const _UCFilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? AppTheme.primary : AppTheme.divider),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.textSecondary)),
      ),
    );
  }
}

// â”€â”€ Booking tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});
  final dynamic booking;

  @override
  Widget build(BuildContext context) {
    Color statusColor() {
      final s = (booking.status.name as String);
      if (s == 'closed') return Colors.green;
      if (s.contains('service') || s.contains('bill')) return AppTheme.accent;
      if (s == 'booked') return AppTheme.badgeOrange;
      return AppTheme.primary;
    }

    return GestureDetector(
      onTap: () => context.push('/booking/${booking.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.divider)),
              child: const Icon(Icons.home_repair_service_outlined,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.applianceType as String,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 3),
                  Text(booking.preferredTime as String,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor().withValues(alpha: 0.3)),
              ),
              child: Text(booking.status.label as String,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor())),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 18),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Bottom nav â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _UCBottomNav extends StatelessWidget {
  const _UCBottomNav({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: index,
        onTap: onTap,
        backgroundColor: AppTheme.background,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textHint,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Bookings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Explore'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}

// â”€â”€ Service search delegate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ServiceSearchDelegate extends SearchDelegate<String> {
  _ServiceSearchDelegate({required this.categories});
  final List<ApplianceCategory> categories;

  // All searchable items: category names + most booked labels
  static const _bookedLabels = [
    'Bathroom Cleaning',
    'AC Repair',
    'Foam-jet AC Service',
    'Kitchen Cleaning',
    'Fan Repair',
  ];

  List<String> get _allTerms => [
        ..._bookedLabels,
        ...categories.map((c) => c.name),
      ];

  List<String> _results(String q) {
    if (q.trim().isEmpty) return [];
    final lower = q.toLowerCase();
    return _allTerms.where((t) => t.toLowerCase().contains(lower)).toList();
  }

  @override
  String get searchFieldLabel => "Search for 'AC service'";

  @override
  TextStyle get searchFieldStyle => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppTheme.textPrimary,
      );

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primary),
        titleTextStyle: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppTheme.textHint, fontSize: 14),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context, query);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context, query);

  Widget _buildList(BuildContext context, String q) {
    final results = _results(q);

    if (q.trim().isEmpty) {
      // Show recent / popular when no query
      return _SuggestionsView(
        categories: categories,
        onTap: (name) {
          query = name;
          showResults(context);
        },
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(
              'No results for "$q"',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a different keyword',
              style: TextStyle(fontSize: 13, color: AppTheme.textHint),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 56, color: AppTheme.divider),
      itemBuilder: (context, i) {
        final name = results[i];
        return ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Icon(
              _iconFor(name),
              size: 18,
              color: AppTheme.primary,
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 13, color: AppTheme.textHint),
          onTap: () {
            close(context, name);
            context.push('/book/${Uri.encodeComponent(name)}');
          },
        );
      },
    );
  }

  IconData _iconFor(String name) => switch (name) {
        'Air Conditioner' ||
        'AC Repair' ||
        'Foam-jet AC Service' =>
          Icons.ac_unit,
        'Refrigerator' => Icons.kitchen,
        'Washing Machine' => Icons.local_laundry_service,
        'Microwave' => Icons.microwave,
        'Water Purifier' => Icons.water_drop,
        'Television' => Icons.tv,
        'Fan' || 'Fan Repair' => Icons.air,
        'Bathroom Cleaning' => Icons.bathtub_outlined,
        'Kitchen Cleaning' => Icons.kitchen,
        _ => Icons.home_repair_service,
      };
}

// â”€â”€ Suggestions view shown when search is empty â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SuggestionsView extends StatelessWidget {
  const _SuggestionsView({required this.categories, required this.onTap});
  final List<ApplianceCategory> categories;
  final void Function(String) onTap;

  static const _popular = [
    'AC Repair',
    'Bathroom Cleaning',
    'Fan Repair',
    'Kitchen Cleaning',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Popular searches',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popular
              .map(
                (label) => GestureDetector(
                  onTap: () => onTap(label),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.trending_up,
                            size: 13, color: AppTheme.badgeOrange),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text(
          'Browse categories',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        ...categories.map(
          (c) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(
                _iconFor(c.name),
                size: 18,
                color: AppTheme.primary,
              ),
            ),
            title: Text(
              c.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 13, color: AppTheme.textHint),
            onTap: () => onTap(c.name),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String name) => switch (name) {
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
