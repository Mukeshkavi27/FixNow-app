import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_scaffold.dart';
import '../../../app/widgets/resilient_asset_image.dart';
import '../../../core/branches/branch_info.dart';
import '../../../core/branches/branch_repository.dart';
import '../../../core/branches/branch_resolver.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/booking_status.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/domain/bill.dart';
import '../../technician/data/technician_repository.dart';
import '../../technician/domain/attendance.dart';
import '../../technician/domain/technician_location.dart';
import '../data/admin_repository.dart';
import '../../bookings/presentation/booking_detail_screen.dart';
import 'admin_dashboard_support.dart';

final allBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingRepositoryProvider).watchAllBookings();
});

final techniciansProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchTechnicians();
});

final customersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchCustomers();
});

final allBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  return ref.watch(billRepositoryProvider).watchAllBills();
});

final activeTechnicianLocationsProvider =
    StreamProvider.autoDispose<List<TechnicianLocation>>((ref) {
  return ref.watch(technicianRepositoryProvider).watchActiveLocations();
});

final attendanceProvider = StreamProvider.autoDispose<List<Attendance>>((ref) {
  return ref.watch(technicianRepositoryProvider).watchAttendance();
});

final pendingTechnicianRequestsProvider =
    StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchPendingTechnicianRequests();
});

String _registeredTechnicianName(AppUser technician) {
  final name = technician.name.trim();
  if (name.isNotEmpty) return name;
  final phone = technician.phone.trim();
  if (phone.isNotEmpty) return phone;
  final email = technician.email.trim();
  return email.isNotEmpty ? email : 'Unnamed technician';
}

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _searchController = TextEditingController();
  BookingStatus? _selectedStatus;
  String? _selectedTechnicianId;
  AdminRangeFilter _selectedRange = AdminRangeFilter.all;
  String? _selectedBranchId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);
    final bookingsAsync = ref.watch(allBookingsProvider);
    final techniciansAsync = ref.watch(techniciansProvider);
    final customersAsync = ref.watch(customersProvider);
    final billsAsync = ref.watch(allBillsProvider);
    final locationsAsync = ref.watch(activeTechnicianLocationsProvider);
    final attendanceAsync = ref.watch(attendanceProvider);
    final pendingRequestsAsync = ref.watch(pendingTechnicianRequestsProvider);
    final currentAdmin = ref.watch(currentUserProvider).valueOrNull;

    return AppScaffold(
      title: 'Admin Dashboard',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _manualBooking(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Manual Booking'),
      ),
      body: branchesAsync.when(
        loading: () => const _AdminStatePanel(
          title: 'Loading branches',
          message: 'Fetching branch configuration for the admin console.',
          icon: Icons.sync,
          busy: true,
        ),
        error: (error, _) => _AdminError(
          message: error.toString(),
          onRetry: () => ref.invalidate(branchesProvider),
        ),
        data: (branches) {
          if (branches.isEmpty) {
            return _AdminEmptyBranches(
              onAddBranch: () => _openBranchDialog(context, ref),
            );
          }
          final effectiveBranchId =
              _selectedBranchId ?? currentAdmin?.branchId ?? branches.first.id;
          final effectiveBranch =
              _branchById(branches, effectiveBranchId) ?? branches.first;

          return bookingsAsync.when(
            loading: () => const _AdminStatePanel(
              title: 'Loading bookings',
              message: 'Preparing today\'s jobs and service queue.',
              icon: Icons.receipt_long_outlined,
              busy: true,
            ),
            error: (error, _) => _AdminError(
              message: error.toString(),
              onRetry: () => ref.invalidate(allBookingsProvider),
            ),
            data: (bookings) => techniciansAsync.when(
              loading: () => const _AdminStatePanel(
                title: 'Loading technicians',
                message: 'Getting technician roster and assignment controls.',
                icon: Icons.engineering_outlined,
                busy: true,
              ),
              error: (error, _) => _AdminError(
                message: error.toString(),
                onRetry: () => ref.invalidate(techniciansProvider),
              ),
              data: (technicians) => billsAsync.when(
                loading: () => const _AdminStatePanel(
                  title: 'Loading billing',
                  message: 'Calculating collections and revenue metrics.',
                  icon: Icons.payments_outlined,
                  busy: true,
                ),
                error: (error, _) => _AdminError(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(allBillsProvider),
                ),
                data: (bills) {
                  final now = DateTime.now();
                  final branchBookings = bookings.where((booking) {
                    return booking.branchId == effectiveBranchId ||
                        booking.branchName == effectiveBranch.name ||
                        booking.branchName == effectiveBranch.city ||
                        booking.branchId == null ||
                        booking.branchId!.isEmpty;
                  }).toList();
                  final branchTechnicians = technicians
                      .where((technician) =>
                          technician.branchId == effectiveBranchId)
                      .toList();
                  if (customersAsync.hasError) {
                    return _AdminError(
                      message: customersAsync.error.toString(),
                      onRetry: () => ref.invalidate(customersProvider),
                    );
                  }
                  if (customersAsync.isLoading) {
                    return const _AdminStatePanel(
                      title: 'Loading customers',
                      message: 'Fetching branch customers and profile counts.',
                      icon: Icons.people_outline,
                      busy: true,
                    );
                  }
                  final branchCustomers = (customersAsync.valueOrNull ??
                          const <AppUser>[])
                      .where(
                          (customer) => customer.branchId == effectiveBranchId)
                      .toList();
                  final filteredBookings = filterAdminBookings(
                    bookings: branchBookings,
                    now: now,
                    query: _searchController.text,
                    status: _selectedStatus,
                    technicianId: _selectedTechnicianId,
                    range: _selectedRange,
                  );
                  final overdueBookings = branchBookings
                      .where((booking) => isBookingOverdue(booking, now))
                      .toList();
                  final dueSoonBookings = branchBookings.where((booking) {
                    final deadline = bookingDeadline(booking);
                    if (deadline == null || isBookingOverdue(booking, now)) {
                      return false;
                    }
                    return deadline.difference(now) <= const Duration(hours: 1);
                  }).length;
                  final paidBills = bills.where((bill) => bill.isPaid).toList();
                  final revenueToday = paidBills
                      .where((bill) => isSameDay(bill.createdAt, now))
                      .fold<double>(0, (sum, bill) => sum + bill.amount);
                  final revenueMonth = paidBills
                      .where((bill) =>
                          bill.createdAt.year == now.year &&
                          bill.createdAt.month == now.month)
                      .fold<double>(0, (sum, bill) => sum + bill.amount);

                  return locationsAsync.when(
                    loading: () => const _AdminStatePanel(
                      title: 'Loading live tracking',
                      message:
                          'Connecting technician locations and map markers.',
                      icon: Icons.location_searching_outlined,
                      busy: true,
                    ),
                    error: (error, _) => _AdminError(
                      message: error.toString(),
                      onRetry: () =>
                          ref.invalidate(activeTechnicianLocationsProvider),
                    ),
                    data: (locations) {
                      final performance = buildTechnicianPerformance(
                        technicians: branchTechnicians,
                        bills: bills,
                        bookings: branchBookings,
                        locations: locations,
                        now: now,
                      );
                      final pendingRequests = (pendingRequestsAsync
                                  .valueOrNull ??
                              const <AppUser>[])
                          .where((item) => item.branchId == effectiveBranchId)
                          .toList();
                      final attendanceProviderValue =
                          attendanceAsync.valueOrNull ?? const <Attendance>[];
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(allBookingsProvider);
                          ref.invalidate(techniciansProvider);
                          ref.invalidate(allBillsProvider);
                          ref.invalidate(activeTechnicianLocationsProvider);
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _AdminHero(
                                activeTechnicians: branchTechnicians
                                    .where((tech) => tech.isActive)
                                    .length,
                                totalCustomers: branchCustomers.length,
                                overdueJobs: overdueBookings.length,
                                branchName: effectiveBranch.name,
                              ),
                              const SizedBox(height: 18),
                              _BranchManagementSection(
                                branches: branches,
                                activeBranchId: effectiveBranch.id,
                                onAddBranch: () =>
                                    _openBranchDialog(context, ref),
                                onEditBranch: (branch) => _openBranchDialog(
                                    context, ref,
                                    branch: branch),
                                onSelectBranch: (branch) => setState(
                                  () => _selectedBranchId = branch.id,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _AdminMetricGrid(
                                metrics: [
                                  _MetricData(
                                    label: 'Filtered bookings',
                                    value: '${filteredBookings.length}',
                                    caption:
                                        '${branchBookings.length} total jobs',
                                    color: AppTheme.primary,
                                    icon: Icons.filter_alt_outlined,
                                  ),
                                  _MetricData(
                                    label: 'Revenue today',
                                    value: _formatCurrency(revenueToday),
                                    caption: 'Paid bills only',
                                    color: AppTheme.accent,
                                    icon: Icons.currency_rupee,
                                  ),
                                  _MetricData(
                                    label: 'Revenue month',
                                    value: _formatCurrency(revenueMonth),
                                    caption: 'This month',
                                    color: const Color(0xFF6B7CFF),
                                    icon: Icons.insights_outlined,
                                  ),
                                  _MetricData(
                                    label: 'Jobs at risk',
                                    value: '${overdueBookings.length}',
                                    caption:
                                        '$dueSoonBookings due within 1 hour',
                                    color: const Color(0xFFD95C2A),
                                    icon: Icons.alarm_on_outlined,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _AdminFilterPanel(
                                controller: _searchController,
                                selectedStatus: _selectedStatus,
                                selectedTechnicianId: _selectedTechnicianId,
                                selectedRange: _selectedRange,
                                technicians: branchTechnicians,
                                onSearchChanged: (_) => setState(() {}),
                                onStatusChanged: (value) =>
                                    setState(() => _selectedStatus = value),
                                onTechnicianChanged: (value) => setState(
                                  () => _selectedTechnicianId =
                                      value == 'all' ? null : value,
                                ),
                                onRangeChanged: (value) =>
                                    setState(() => _selectedRange = value),
                                onClear: () {
                                  setState(() {
                                    _searchController.clear();
                                    _selectedStatus = null;
                                    _selectedTechnicianId = null;
                                    _selectedRange = AdminRangeFilter.all;
                                  });
                                },
                              ),
                              if (pendingRequests.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                _PendingTechnicianSection(
                                  requests: pendingRequests,
                                  branches: branches,
                                ),
                              ],
                              const SizedBox(height: 18),
                              _LiveMonitoringSection(
                                locations: locations
                                    .where(
                                      (location) => branchTechnicians.any(
                                        (technician) =>
                                            technician.uid ==
                                            location.technicianId,
                                      ),
                                    )
                                    .toList(),
                                bookings: branchBookings,
                                selectedTechnicianId: _selectedTechnicianId,
                                branchName: effectiveBranch.name,
                                branchCity: effectiveBranch.city,
                              ),
                              const SizedBox(height: 18),
                              _TechnicianWorkspaceSection(
                                performance: performance,
                                bookings: branchBookings,
                                locations: locations,
                                attendance: attendanceProviderValue,
                                attendanceLoading: attendanceAsync.isLoading,
                              ),
                              const SizedBox(height: 18),
                              _SectionCard(
                                title: 'Booking control',
                                subtitle:
                                    'Filter, assign, collect payments, and watch service deadlines.',
                                action: FilledButton.icon(
                                  onPressed: branchTechnicians
                                          .where((tech) => tech.isActive)
                                          .isEmpty
                                      ? null
                                      : () => _autoAllocateBranchBookings(
                                            context: context,
                                            ref: ref,
                                            bookings: branchBookings,
                                            technicians: branchTechnicians,
                                            locations: locations,
                                          ),
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('Auto allocate all'),
                                ),
                                child: filteredBookings.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'No bookings match the current filters.',
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          for (var i = 0;
                                              i < filteredBookings.length;
                                              i++) ...[
                                            _AdminBookingCard(
                                              booking: filteredBookings[i],
                                              now: now,
                                              branchTechnicians:
                                                  branchTechnicians,
                                              allTechnicians: technicians,
                                              allBookings: bookings,
                                            ),
                                            if (i !=
                                                filteredBookings.length - 1)
                                              const SizedBox(height: 12),
                                          ],
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _manualBooking(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final appliance = TextEditingController();
    final problem = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Manual phone booking'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Customer name'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: appliance,
                      decoration: const InputDecoration(labelText: 'Appliance'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: problem,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Problem description',
                      ),
                      validator: _required,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final now = DateTime.now();
                final currentAdmin = ref.read(currentUserProvider).valueOrNull;
                final branches =
                    ref.read(branchesProvider).valueOrNull ?? const [];
                if (branches.isEmpty) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Add a branch before creating bookings.'),
                      ),
                    );
                  }
                  return;
                }
                final branch = currentAdmin?.branchId != null
                    ? _branchById(branches, currentAdmin!.branchId) ??
                        branches.first
                    : BranchResolver.resolve(
                        branches: branches,
                        address: address.text.trim(),
                      ).branch;
                await ref.read(bookingRepositoryProvider).createBooking(
                      Booking(
                        id: '',
                        customerId: 'manual_${const Uuid().v4()}',
                        customerName: name.text.trim(),
                        phone: phone.text.trim(),
                        address: address.text.trim(),
                        applianceType: appliance.text.trim(),
                        problemDescription: problem.text.trim(),
                        preferredDate: now.add(const Duration(days: 1)),
                        preferredTime: 'To be confirmed',
                        status: BookingStatus.booked,
                        createdAt: now,
                        branchId: branch.id,
                        branchName: branch.name,
                      ),
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Create booking'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
      appliance.dispose();
      problem.dispose();
    }
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  BranchInfo? _branchById(List<BranchInfo> branches, String? branchId) {
    if (branchId == null) return null;
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    return null;
  }

  Future<void> _autoAllocateBranchBookings({
    required BuildContext context,
    required WidgetRef ref,
    required List<Booking> bookings,
    required List<AppUser> technicians,
    required List<TechnicianLocation> locations,
  }) async {
    final activeTechnicians =
        technicians.where((technician) => technician.isActive).toList();
    final unassignedBookings = bookings
        .where((booking) => booking.status == BookingStatus.booked)
        .where((booking) => booking.technicianId == null)
        .toList();
    if (activeTechnicians.isEmpty || unassignedBookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unassigned bookings to allocate.')),
      );
      return;
    }

    final locationByTechnician = {
      for (final location in locations) location.technicianId: location,
    };
    final activeLoad = <String, int>{
      for (final technician in activeTechnicians) technician.uid: 0,
    };
    for (final booking in bookings) {
      final technicianId = booking.technicianId;
      if (technicianId != null &&
          activeLoad.containsKey(technicianId) &&
          booking.status != BookingStatus.closed) {
        activeLoad[technicianId] = activeLoad[technicianId]! + 1;
      }
    }

    var allocated = 0;
    for (final booking in unassignedBookings) {
      final technician = _recommendedTechnicianForBooking(
        booking: booking,
        technicians: activeTechnicians,
        locationByTechnician: locationByTechnician,
        activeLoad: activeLoad,
      );
      if (technician == null) continue;
      await ref.read(bookingRepositoryProvider).assignTechnician(
            bookingId: booking.id,
            technicianId: technician.uid,
            technicianName: _registeredTechnicianName(technician),
          );
      activeLoad[technician.uid] = (activeLoad[technician.uid] ?? 0) + 1;
      allocated++;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Auto allocated $allocated booking(s).')),
    );
  }

  AppUser? _recommendedTechnicianForBooking({
    required Booking booking,
    required List<AppUser> technicians,
    required Map<String, TechnicianLocation> locationByTechnician,
    required Map<String, int> activeLoad,
  }) {
    if (technicians.isEmpty) return null;
    final ranked = [...technicians];
    ranked.sort((left, right) {
      final leftDistance = _distanceToBooking(
        booking,
        locationByTechnician[left.uid],
      );
      final rightDistance = _distanceToBooking(
        booking,
        locationByTechnician[right.uid],
      );
      final leftHasDistance = !leftDistance.isInfinite;
      final rightHasDistance = !rightDistance.isInfinite;
      if (leftHasDistance != rightHasDistance) {
        return leftHasDistance ? -1 : 1;
      }
      if (leftHasDistance && rightHasDistance) {
        final distanceCompare = leftDistance.compareTo(rightDistance);
        if (distanceCompare != 0) return distanceCompare;
      }
      final loadCompare =
          (activeLoad[left.uid] ?? 0).compareTo(activeLoad[right.uid] ?? 0);
      if (loadCompare != 0) return loadCompare;
      return left.name.compareTo(right.name);
    });
    return ranked.first;
  }

  double _distanceToBooking(
    Booking booking,
    TechnicianLocation? location,
  ) {
    if (booking.latitude == null ||
        booking.longitude == null ||
        location == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      booking.latitude!,
      booking.longitude!,
      location.latitude,
      location.longitude,
    );
  }

  Future<void> _openBranchDialog(
    BuildContext context,
    WidgetRef ref, {
    BranchInfo? branch,
  }) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: branch?.name ?? '');
    final city = TextEditingController(text: branch?.city ?? '');
    final aliases = TextEditingController(
      text: branch == null ? '' : branch.aliases.join(', '),
    );
    final radius = TextEditingController(
      text: branch == null ? '35000' : branch.radiusMeters.toStringAsFixed(0),
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(branch == null ? 'Add branch' : 'Edit branch'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Branch name'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: radius,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Service radius (meters)',
                      ),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: aliases,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Aliases',
                        helperText: 'Comma-separated area names and spellings',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final parsedRadius = double.tryParse(radius.text.trim());
                if (parsedRadius == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid service radius.'),
                    ),
                  );
                  return;
                }
                try {
                  final payload = BranchInfo(
                    id: branch?.id ?? '',
                    name: name.text.trim(),
                    city: city.text.trim(),
                    latitude: branch?.latitude ?? 0,
                    longitude: branch?.longitude ?? 0,
                    aliases: aliases.text
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(),
                    radiusMeters: parsedRadius,
                  );
                  final repository = ref.read(branchRepositoryProvider);
                  if (branch == null) {
                    await repository.createBranch(payload);
                  } else {
                    await repository.updateBranch(payload);
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          branch == null
                              ? 'Branch created successfully.'
                              : 'Branch updated successfully.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(error.toString()),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                }
              },
              child: Text(branch == null ? 'Create branch' : 'Save branch'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      city.dispose();
      aliases.dispose();
      radius.dispose();
    }
  }
}

class _BranchManagementSection extends StatelessWidget {
  const _BranchManagementSection({
    required this.branches,
    required this.activeBranchId,
    required this.onAddBranch,
    required this.onEditBranch,
    this.onSelectBranch,
  });

  final List<BranchInfo> branches;
  final String activeBranchId;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;
  final ValueChanged<BranchInfo>? onSelectBranch;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Branches',
      subtitle:
          'Manage cities, service radius, and area aliases that route customers and technicians automatically.',
      action: FilledButton.icon(
        onPressed: onAddBranch,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add branch'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 3
              : constraints.maxWidth >= 760
                  ? 2
                  : 1;
          final spacing = 12.0;
          final cardWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final branch in branches)
                SizedBox(
                  width: cardWidth,
                  child: _BranchCard(
                    branch: branch,
                    selected: branch.id == activeBranchId,
                    onSelected: onSelectBranch == null
                        ? null
                        : () => onSelectBranch!(branch),
                    onEdit: () => onEditBranch(branch),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
  });

  final BranchInfo branch;
  final bool selected;
  final VoidCallback? onSelected;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 228),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    branch.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit branch',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            Text(
              branch.city,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            _StatusPill(
              label:
                  'Radius ${(branch.radiusMeters / 1000).toStringAsFixed(0)} km',
              color: AppTheme.accent,
            ),
            const SizedBox(height: 12),
            const Text(
              'City name and aliases route customers and technicians to this branch.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              branch.aliases.isEmpty
                  ? 'No area aliases added yet.'
                  : 'Aliases: ${branch.aliases.join(', ')}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (selected)
              const Text(
                'Currently selected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminEmptyBranches extends StatelessWidget {
  const _AdminEmptyBranches({required this.onAddBranch});

  final VoidCallback onAddBranch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.location_city_outlined,
                    size: 34,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add your first branch',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bookings, technician approvals, and customer routing need at least one branch. Add a city branch to start operations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAddBranch,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Create branch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingTechnicianSection extends ConsumerWidget {
  const _PendingTechnicianSection({
    required this.requests,
    required this.branches,
  });

  final List<AppUser> requests;
  final List<BranchInfo> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Technician approvals',
      subtitle:
          'Review branch requests before technicians get access to live jobs and attendance.',
      child: Column(
        children: [
          for (var i = 0; i < requests.length; i++) ...[
            _PendingTechnicianTile(
              request: requests[i],
              branches: branches,
            ),
            if (i != requests.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PendingTechnicianTile extends ConsumerWidget {
  const _PendingTechnicianTile({
    required this.request,
    required this.branches,
  });

  final AppUser request;
  final List<BranchInfo> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggested = request.requestLatitude != null &&
            request.requestLongitude != null &&
            branches.isNotEmpty
        ? BranchResolver.resolve(
            branches: branches,
            latitude: request.requestLatitude,
            longitude: request.requestLongitude,
          ).branch
        : null;
    final branchId = request.branchId ?? suggested?.id ?? branches.first.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${request.phone} | ${request.email}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: request.branchName ?? 'Requested branch pending',
                color: AppTheme.primary,
              ),
              if (suggested != null && suggested.id != request.branchId)
                _StatusPill(
                  label: 'Nearest: ${suggested.city}',
                  color: AppTheme.accent,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref
                      .read(adminRepositoryProvider)
                      .rejectTechnicianRequest(request.uid),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    var branch = branches.first;
                    for (final item in branches) {
                      if (item.id == branchId) {
                        branch = item;
                        break;
                      }
                    }
                    ref.read(adminRepositoryProvider).approveTechnicianRequest(
                          uid: request.uid,
                          branchId: branch.id,
                          branchName: branch.name,
                        );
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.activeTechnicians,
    required this.totalCustomers,
    required this.overdueJobs,
    required this.branchName,
  });

  final int activeTechnicians;
  final int totalCustomers;
  final int overdueJobs;
  final String branchName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: const ResilientAssetImage(
              assetName: 'assets/images/fix_now_general.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              fallbackIcon: Icons.analytics_outlined,
              fallbackIconSize: 64,
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
                    AppTheme.primary.withValues(alpha: 0.92),
                    AppTheme.primary.withValues(alpha: 0.72),
                    AppTheme.accent.withValues(alpha: 0.42),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(20),
            child: Wrap(
              runSpacing: 16,
              spacing: 16,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operations command center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$branchName is live. Track technician movement, watch overdue jobs, and compare who is earning what today and this month.',
                        style: TextStyle(
                          color: Color(0xFFE8F1FF),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _HeroTag(
                      label: 'Active technicians',
                      value: '$activeTechnicians',
                    ),
                    _HeroTag(
                      label: 'Customers',
                      value: '$totalCustomers',
                    ),
                    _HeroTag(
                      label: 'Overdue jobs',
                      value: '$overdueJobs',
                      danger: overdueJobs > 0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger
            ? Colors.white.withValues(alpha: 0.17)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEAF2FF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMetricGrid extends StatelessWidget {
  const _AdminMetricGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 760
                ? 2
                : 1;
        final spacing = 14.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: cardWidth,
                child: _MetricCard(data: metric),
              ),
          ],
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color),
          ),
          const SizedBox(height: 18),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.caption,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFilterPanel extends StatelessWidget {
  const _AdminFilterPanel({
    required this.controller,
    required this.selectedStatus,
    required this.selectedTechnicianId,
    required this.selectedRange,
    required this.technicians,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onTechnicianChanged,
    required this.onRangeChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final BookingStatus? selectedStatus;
  final String? selectedTechnicianId;
  final AdminRangeFilter selectedRange;
  final List<AppUser> technicians;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<BookingStatus?> onStatusChanged;
  final ValueChanged<String?> onTechnicianChanged;
  final ValueChanged<AdminRangeFilter> onRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selectedTechnicianValue = selectedTechnicianId == null ||
            selectedTechnicianId == 'all' ||
            technicians.any((tech) => tech.uid == selectedTechnicianId)
        ? (selectedTechnicianId ?? 'all')
        : 'all';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;
              final searchField = TextField(
                controller: controller,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search customer, appliance, phone, address',
                ),
              );
              final statusField = DropdownButtonFormField<BookingStatus?>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status filter',
                ),
                items: [
                  const DropdownMenuItem<BookingStatus?>(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ...BookingStatus.values.map(
                    (status) => DropdownMenuItem<BookingStatus?>(
                      value: status,
                      child: Text(status.label),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              );
              final technicianField = DropdownButtonFormField<String?>(
                initialValue: selectedTechnicianValue,
                decoration: const InputDecoration(
                  labelText: 'Technician filter',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: 'all',
                    child: Text('All technicians'),
                  ),
                  ...technicians.map(
                    (tech) => DropdownMenuItem<String?>(
                      value: tech.uid,
                      child: Text(tech.name),
                    ),
                  ),
                ],
                onChanged: onTechnicianChanged,
              );

              if (stacked) {
                return Column(
                  children: [
                    searchField,
                    const SizedBox(height: 12),
                    statusField,
                    const SizedBox(height: 12),
                    technicianField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: searchField,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: statusField,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: technicianField,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final range in AdminRangeFilter.values)
                      ChoiceChip(
                        label: Text(range.label),
                        selected: selectedRange == range,
                        onSelected: (_) => onRangeChanged(range),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveMonitoringSection extends StatelessWidget {
  const _LiveMonitoringSection({
    required this.locations,
    required this.bookings,
    required this.selectedTechnicianId,
    required this.branchName,
    required this.branchCity,
  });

  final List<TechnicianLocation> locations;
  final List<Booking> bookings;
  final String? selectedTechnicianId;
  final String branchName;
  final String branchCity;

  @override
  Widget build(BuildContext context) {
    final visibleLocations = selectedTechnicianId == null
        ? locations
        : locations
            .where((location) => location.technicianId == selectedTechnicianId)
            .toList();
    final activeByTechnician = {
      for (final booking in bookings)
        if (booking.technicianId != null &&
            booking.status != BookingStatus.closed)
          booking.technicianId!: booking,
    };

    return _SectionCard(
      title: 'Live monitoring',
      subtitle:
          'Watch all technicians at once and cross-check who is moving, idle, or overdue.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 360,
            child: visibleLocations.isEmpty
                ? _EmptyBranchMapState(
                    branchName: branchName,
                    branchCity: branchCity,
                  )
                : _TechnicianMap(
                    locations: visibleLocations,
                    activeByTechnician: activeByTechnician,
                  ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MonitorChip(
                label: 'Visible technicians',
                value: '${visibleLocations.length}',
                color: AppTheme.primary,
              ),
              _MonitorChip(
                label: 'On active jobs',
                value: '${activeByTechnician.length}',
                color: AppTheme.accent,
              ),
              _MonitorChip(
                label: 'Stale location updates',
                value:
                    '${visibleLocations.where((location) => DateTime.now().difference(location.updatedAt) > const Duration(minutes: 15)).length}',
                color: const Color(0xFFD95C2A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonitorChip extends StatelessWidget {
  const _MonitorChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

class _TechnicianWorkspaceSection extends StatelessWidget {
  const _TechnicianWorkspaceSection({
    required this.performance,
    required this.bookings,
    required this.locations,
    required this.attendance,
    required this.attendanceLoading,
  });

  final List<TechnicianPerformance> performance;
  final List<Booking> bookings;
  final List<TechnicianLocation> locations;
  final List<Attendance> attendance;
  final bool attendanceLoading;

  @override
  Widget build(BuildContext context) {
    final attendanceByTechnician = <String, List<Attendance>>{};
    for (final record in attendance) {
      attendanceByTechnician.putIfAbsent(record.technicianId, () => []);
      attendanceByTechnician[record.technicianId]!.add(record);
    }
    final locationByTechnician = {
      for (final location in locations) location.technicianId: location,
    };
    final activeBookingsByTechnician = <String, List<Booking>>{};
    for (final booking in bookings) {
      final technicianId = booking.technicianId;
      if (technicianId == null || booking.status == BookingStatus.closed) {
        continue;
      }
      activeBookingsByTechnician.putIfAbsent(technicianId, () => []);
      activeBookingsByTechnician[technicianId]!.add(booking);
    }
    final needsReview =
        attendance.where((record) => !record.geofencePassed).length;

    return _SectionCard(
      title: 'Technician availability & attendance',
      subtitle:
          'Available technicians, attendance, admin review, and live status.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniStat(label: 'Technicians', value: '${performance.length}'),
              _MiniStat(
                label: 'Available',
                value:
                    '${performance.where((item) => item.technician.isActive).length}',
              ),
              _MiniStat(
                  label: 'Attendance entries', value: '${attendance.length}'),
              _MiniStat(label: 'Needs review', value: '$needsReview'),
            ],
          ),
          const SizedBox(height: 14),
          if (attendanceLoading && attendance.isEmpty)
            const _InlineEmptyState(
              icon: Icons.sync,
              message: 'Loading attendance records.',
            )
          else if (performance.isEmpty)
            const _InlineEmptyState(
              icon: Icons.engineering_outlined,
              message: 'No technicians are approved for this branch yet.',
            )
          else
            Column(
              children: [
                for (var i = 0; i < performance.length; i++) ...[
                  _TechnicianAvailabilityRow(
                    item: performance[i],
                    records:
                        attendanceByTechnician[performance[i].technician.uid] ??
                            const [],
                    location:
                        locationByTechnician[performance[i].technician.uid],
                    activeBookings: activeBookingsByTechnician[
                            performance[i].technician.uid] ??
                        const [],
                  ),
                  if (i != performance.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TechnicianAvailabilityRow extends ConsumerWidget {
  const _TechnicianAvailabilityRow({
    required this.item,
    required this.records,
    required this.location,
    required this.activeBookings,
  });

  final TechnicianPerformance item;
  final List<Attendance> records;
  final TechnicianLocation? location;
  final List<Booking> activeBookings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technician = item.technician;
    final latest = records.isEmpty ? null : records.first;
    final reviewCount =
        records.where((record) => !record.geofencePassed).length;
    final locationText = location == null
        ? 'No live location'
        : 'Location ${_formatRelative(location!.updatedAt)}';
    final attendanceText = latest == null
        ? 'No attendance marked'
        : 'In ${DateFormat('dd MMM, hh:mm a').format(latest.timestamp)}';
    final availabilityColor =
        technician.isActive ? AppTheme.accent : const Color(0xFFD95C2A);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: availabilityColor.withValues(alpha: 0.12),
                foregroundColor: availabilityColor,
                child: Text(
                  technician.name.isEmpty
                      ? 'T'
                      : technician.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      technician.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${technician.phone} - ${technician.email}',
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
              Switch(
                value: technician.isActive,
                onChanged: (value) => ref
                    .read(adminRepositoryProvider)
                    .setTechnicianActive(technician.uid, value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: technician.isActive ? 'Available' : 'Inactive',
                color: availabilityColor,
              ),
              _StatusPill(
                label: '${activeBookings.length} active job(s)',
                color: AppTheme.primary,
              ),
              _StatusPill(
                label: records.isEmpty ? 'Attendance missing' : attendanceText,
                color:
                    records.isEmpty ? const Color(0xFFD95C2A) : AppTheme.accent,
              ),
              _StatusPill(
                label: '$reviewCount admin review',
                color:
                    reviewCount > 0 ? const Color(0xFFD95C2A) : AppTheme.accent,
              ),
              _StatusPill(
                label: locationText,
                color: item.highlightRisk
                    ? const Color(0xFFD95C2A)
                    : AppTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBookingCard extends ConsumerWidget {
  const _AdminBookingCard({
    required this.booking,
    required this.now,
    required this.branchTechnicians,
    required this.allTechnicians,
    required this.allBookings,
  });

  final Booking booking;
  final DateTime now;
  final List<AppUser> branchTechnicians;
  final List<AppUser> allTechnicians;
  final List<Booking> allBookings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations =
        ref.watch(activeTechnicianLocationsProvider).valueOrNull ??
            <TechnicianLocation>[];
    final locationByTechnician = {
      for (final location in locations) location.technicianId: location,
    };
    final branchTechnicianIds = {
      for (final technician in branchTechnicians) technician.uid,
    };
    final activeLoad = <String, int>{};
    for (final item in allBookings) {
      final technicianId = item.technicianId;
      if (technicianId == null || item.status == BookingStatus.closed) {
        continue;
      }
      activeLoad[technicianId] = (activeLoad[technicianId] ?? 0) + 1;
    }
    final technicians = allTechnicians
        .where(
          (tech) =>
              tech.isActive && tech.accountStatus == AccountStatus.approved,
        )
        .toList()
      ..sort(
        (left, right) => _compareTechnicianPriority(
          left: left,
          right: right,
          booking: booking,
          branchTechnicianIds: branchTechnicianIds,
          locationByTechnician: locationByTechnician,
          activeLoad: activeLoad,
        ),
      );
    final technicianById = {
      for (final technician in technicians) technician.uid: technician,
    };
    final recommendedTechnician =
        technicians.isEmpty ? null : technicians.first;
    final bill = ref.watch(bookingBillProvider(booking.id)).valueOrNull;
    final canChangeTechnician = booking.status != BookingStatus.closed;
    final assignmentValue = booking.technicianId != null &&
            technicianById.containsKey(booking.technicianId)
        ? booking.technicianId
        : null;
    final overdue = isBookingOverdue(booking, now);
    final deadline = bookingDeadline(booking);
    final dueSoon = !overdue &&
        deadline != null &&
        deadline.difference(now) <= const Duration(hours: 1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: overdue
              ? const Color(0xFFF0C4B4)
              : dueSoon
                  ? const Color(0xFFFFD6A8)
                  : AppTheme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${booking.applianceType} - ${booking.customerName}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        _StatusPill(
                          label: booking.status.label,
                          color: _statusColor(booking.status),
                        ),
                        if (overdue)
                          const _StatusPill(
                            label: 'Overdue',
                            color: Color(0xFFD95C2A),
                          )
                        else if (dueSoon)
                          const _StatusPill(
                            label: 'Due soon',
                            color: Color(0xFFF38A1F),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${booking.phone} - ${booking.address}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      booking.problemDescription,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/booking/${booking.id}'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BookingInfoChip(
                icon: Icons.calendar_today_outlined,
                label: DateFormat('dd MMM, hh:mm a')
                    .format(bookingScheduledAt(booking)!),
              ),
              _BookingInfoChip(
                icon: Icons.engineering_outlined,
                label: booking.technicianName ?? 'Unassigned',
              ),
              if (deadline != null)
                _BookingInfoChip(
                  icon: Icons.timer_outlined,
                  label: overdue
                      ? 'Missed deadline by ${_formatDuration(now.difference(deadline))}'
                      : 'Window closes in ${_formatDuration(deadline.difference(now))}',
                ),
              if (bill != null)
                _BookingInfoChip(
                  icon: bill.isPaid
                      ? Icons.payments_outlined
                      : Icons.currency_rupee,
                  label:
                      '${bill.isPaid ? 'Paid' : 'Pending'} ${_formatCurrency(bill.amount)}',
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (technicians.isEmpty)
            const _AssignmentEmptyState()
          else ...[
            if (booking.technicianId == null &&
                recommendedTechnician != null) ...[
              _RecommendedTechnicianBanner(
                technician: recommendedTechnician,
                label: _technicianLabel(
                  recommendedTechnician,
                  booking,
                  locationByTechnician[recommendedTechnician.uid],
                  branchPriority:
                      branchTechnicianIds.contains(recommendedTechnician.uid),
                  activeJobs: activeLoad[recommendedTechnician.uid] ?? 0,
                ),
                onAssign: () => _assignTechnician(
                  context: context,
                  ref: ref,
                  technician: recommendedTechnician,
                ),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: assignmentValue,
              decoration: InputDecoration(
                labelText: booking.technicianId == null
                    ? 'Assign technician'
                    : 'Change technician',
                prefixIcon: const Icon(Icons.engineering_outlined),
              ),
              items: technicians
                  .map(
                    (tech) => DropdownMenuItem(
                      value: tech.uid,
                      child: Text(_registeredTechnicianName(tech)),
                    ),
                  )
                  .toList(),
              onChanged: canChangeTechnician
                  ? (uid) {
                      if (uid == null) return;
                      final tech = technicianById[uid];
                      if (tech == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Selected technician is unavailable.'),
                          ),
                        );
                        return;
                      }
                      _assignTechnician(
                        context: context,
                        ref: ref,
                        technician: tech,
                      );
                    }
                  : null,
            ),
          ],
          if (bill != null && !bill.isPaid) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(billRepositoryProvider).markPaid(booking.id),
                icon: const Icon(Icons.payments_outlined),
                label: Text('Mark ${_formatCurrency(bill.amount)} paid'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static double _distanceToBooking(
    Booking booking,
    TechnicianLocation? location,
  ) {
    if (booking.latitude == null ||
        booking.longitude == null ||
        location == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      booking.latitude!,
      booking.longitude!,
      location.latitude,
      location.longitude,
    );
  }

  static String _technicianLabel(
    AppUser technician,
    Booking booking,
    TechnicianLocation? location, {
    bool branchPriority = false,
    int activeJobs = 0,
  }) {
    final distance = _distanceToBooking(booking, location);
    final priority = branchPriority ? 'Branch priority' : 'Available';
    final load = '$activeJobs active job${activeJobs == 1 ? '' : 's'}';
    if (distance.isInfinite) {
      return '${technician.name} - $priority - $load - location unavailable';
    }
    return '${technician.name} - $priority - $load - ${(distance / 1000).toStringAsFixed(1)} km';
  }

  static int _compareTechnicianPriority({
    required AppUser left,
    required AppUser right,
    required Booking booking,
    required Set<String> branchTechnicianIds,
    required Map<String, TechnicianLocation> locationByTechnician,
    required Map<String, int> activeLoad,
  }) {
    final leftBranch = branchTechnicianIds.contains(left.uid);
    final rightBranch = branchTechnicianIds.contains(right.uid);
    if (leftBranch != rightBranch) return leftBranch ? -1 : 1;

    final leftDistance = _distanceToBooking(
      booking,
      locationByTechnician[left.uid],
    );
    final rightDistance = _distanceToBooking(
      booking,
      locationByTechnician[right.uid],
    );
    final leftHasDistance = !leftDistance.isInfinite;
    final rightHasDistance = !rightDistance.isInfinite;
    if (leftHasDistance != rightHasDistance) return leftHasDistance ? -1 : 1;
    if (leftHasDistance && rightHasDistance) {
      final distanceCompare = leftDistance.compareTo(rightDistance);
      if (distanceCompare != 0) return distanceCompare;
    }

    final loadCompare =
        (activeLoad[left.uid] ?? 0).compareTo(activeLoad[right.uid] ?? 0);
    if (loadCompare != 0) return loadCompare;
    return left.name.compareTo(right.name);
  }

  Future<void> _assignTechnician({
    required BuildContext context,
    required WidgetRef ref,
    required AppUser technician,
  }) async {
    try {
      await ref.read(bookingRepositoryProvider).assignTechnician(
            bookingId: booking.id,
            technicianId: technician.uid,
            technicianName: technician.name,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${technician.name} assigned and notified for ${booking.applianceType}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }
}

class _BookingInfoChip extends StatelessWidget {
  const _BookingInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedTechnicianBanner extends StatelessWidget {
  const _RecommendedTechnicianBanner({
    required this.technician,
    required this.label,
    required this.onAssign,
  });

  final AppUser technician;
  final String label;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            !constraints.hasBoundedWidth || constraints.maxWidth < 520;
        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommended: ${technician.name}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final button = SizedBox(
          width: stacked ? double.infinity : 150,
          child: FilledButton.icon(
            onPressed: onAssign,
            icon: const Icon(Icons.bolt_outlined, size: 17),
            label: const Text('Auto assign'),
          ),
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.22)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: 10),
                    button,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 10),
                    button,
                  ],
                ),
        );
      },
    );
  }
}

class _AssignmentEmptyState extends StatelessWidget {
  const _AssignmentEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD88A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.engineering_outlined, color: Color(0xFFD78200)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No active technicians are available in this branch. Activate or approve a technician to allocate this booking.',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TechnicianMap extends StatelessWidget {
  const _TechnicianMap({
    required this.locations,
    required this.activeByTechnician,
  });

  final List<TechnicianLocation> locations;
  final Map<String, Booking> activeByTechnician;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final markers = locations.map((location) {
      final booking = activeByTechnician[location.technicianId];
      final stale =
          now.difference(location.updatedAt) > const Duration(minutes: 15);
      final color = stale
          ? const Color(0xFFD95C2A)
          : booking != null
              ? AppTheme.primary
              : AppTheme.accent;
      return Marker(
        point: LatLng(location.latitude, location.longitude),
        width: 52,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            location.technicianId.isEmpty
                ? 'T'
                : location.technicianId.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }).toList();
    final center =
        markers.isEmpty ? const LatLng(20.5937, 78.9629) : markers.first.point;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: markers.isEmpty ? 4 : 11,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.drag |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.doubleTapZoom,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.fixnow.app',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}

class _EmptyBranchMapState extends StatelessWidget {
  const _EmptyBranchMapState({
    required this.branchName,
    required this.branchCity,
  });

  final String branchName;
  final String branchCity;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            AppTheme.accent.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppTheme.divider),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.location_city_outlined,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '$branchName live map',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No technicians from $branchCity are sharing live location yet.',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Branch routing already works from city and area aliases. The map will switch automatically as soon as this branch has live technician movement.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeader = constraints.maxWidth < 720;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compactHeader) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: action!,
                      ),
                    ],
                  ],
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(width: 12),
                      Flexible(child: action!),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _AdminError extends StatelessWidget {
  const _AdminError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminStatePanel extends StatelessWidget {
  const _AdminStatePanel({
    required this.title,
    required this.message,
    required this.icon,
    this.busy = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: CircularProgressIndicator(),
                  )
                else
                  Icon(icon, size: 44, color: AppTheme.primary),
                if (!busy) const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusColor(BookingStatus status) {
  return switch (status) {
    BookingStatus.booked => const Color(0xFF4B6BFB),
    BookingStatus.technicianAssigned => const Color(0xFF2D8CFF),
    BookingStatus.accepted => const Color(0xFF14A38B),
    BookingStatus.onTheWay => const Color(0xFF0088CC),
    BookingStatus.arrived => const Color(0xFF5C7CFA),
    BookingStatus.estimateSent => const Color(0xFFF08C00),
    BookingStatus.estimateApproved => const Color(0xFF2B8A3E),
    BookingStatus.serviceStarted => const Color(0xFF7B61FF),
    BookingStatus.serviceCompleted => const Color(0xFF1C7ED6),
    BookingStatus.billGenerated => const Color(0xFF845EF7),
    BookingStatus.closed => const Color(0xFF6C757D),
  };
}

String _formatCurrency(double amount) {
  return 'Rs. ${amount.toStringAsFixed(0)}';
}

String _formatDuration(Duration duration) {
  final positive = duration.isNegative ? duration * -1 : duration;
  final hours = positive.inHours;
  final minutes = positive.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${positive.inMinutes}m';
}

String _formatRelative(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return DateFormat('dd MMM, hh:mm a').format(time);
}
