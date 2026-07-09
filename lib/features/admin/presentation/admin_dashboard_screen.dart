import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_scaffold.dart';
import '../../../core/branches/branch_info.dart';
import '../../../core/branches/branch_repository.dart';
import '../../../core/branches/branch_resolver.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/booking_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/maps/google_static_map.dart';
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

const _idleTechnicianThreshold = Duration(minutes: 15);

String _registeredTechnicianName(AppUser technician) {
  final name = technician.name.trim();
  if (name.isNotEmpty) return name;
  final phone = technician.phone.trim();
  if (phone.isNotEmpty) return phone;
  final email = technician.email.trim();
  return email.isNotEmpty ? email : 'Unnamed technician';
}

enum _AdminTab {
  overview('Overview', Icons.dashboard_outlined),
  bookings('Bookings', Icons.assignment_outlined),
  attendance('Attendance', Icons.fact_check_outlined),
  revenue('Revenue', Icons.currency_rupee),
  monitoring('Monitoring', Icons.location_searching_outlined);

  const _AdminTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _BookingSegment {
  ongoing('Ongoing'),
  unassigned('Unassigned'),
  onHold('On hold'),
  closed('Closed');

  const _BookingSegment(this.label);
  final String label;
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
  _AdminTab _selectedAdminTab = _AdminTab.overview;
  _BookingSegment _selectedBookingSegment = _BookingSegment.ongoing;

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
      title: 'FixNow Admin',
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
                    return _bookingMatchesBranch(
                      booking: booking,
                      branch: effectiveBranch,
                      branchId: effectiveBranchId,
                    );
                  }).toList();
                  final branchTechnicians = technicians
                      .where(
                        (technician) => _userMatchesBranch(
                          user: technician,
                          branch: effectiveBranch,
                          branchId: effectiveBranchId,
                        ),
                      )
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
                        (customer) => _userMatchesBranch(
                          user: customer,
                          branch: effectiveBranch,
                          branchId: effectiveBranchId,
                        ),
                      )
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
                          .where(
                            (item) => _userMatchesBranch(
                              user: item,
                              branch: effectiveBranch,
                              branchId: effectiveBranchId,
                            ),
                          )
                          .toList();
                      final attendanceProviderValue =
                          attendanceAsync.valueOrNull ?? const <Attendance>[];
                      final visibleLocations = locations
                          .where(
                            (location) => branchTechnicians.any(
                              (technician) =>
                                  technician.uid == location.technicianId,
                            ),
                          )
                          .toList();
                      final unassignedBookings = branchBookings
                          .where((booking) =>
                              booking.status == BookingStatus.booked &&
                              (booking.technicianId == null ||
                                  booking.technicianId!.isEmpty))
                          .toList();
                      final activeByTechnician = {
                        for (final booking in branchBookings)
                          if (booking.technicianId != null &&
                              isTechnicianBusyStatus(booking.status))
                            booking.technicianId!: booking,
                      };
                      final locationByTechnician = {
                        for (final location in locations)
                          location.technicianId: location,
                      };
                      final idleTechnicians = branchTechnicians.where((tech) {
                        final booking = activeByTechnician[tech.uid];
                        if (booking == null ||
                            booking.status != BookingStatus.onTheWay) {
                          return false;
                        }
                        final location = locationByTechnician[tech.uid];
                        return location == null ||
                            !location.isOnline ||
                            now.difference(location.updatedAt) >
                                _idleTechnicianThreshold;
                      }).toList();
                      final selectedTabContent = switch (_selectedAdminTab) {
                        _AdminTab.overview => _OverviewAdminTab(
                            activeTechnicians: branchTechnicians
                                .where((tech) => tech.isActive)
                                .length,
                            unassignedBookings: unassignedBookings.length,
                            overdueBookings: overdueBookings.length,
                            jobsAtRisk:
                                overdueBookings.length + idleTechnicians.length,
                            idleTechnicians: idleTechnicians.length,
                            onReview: () {
                              setState(() {
                                _selectedAdminTab = _AdminTab.bookings;
                                _selectedBookingSegment =
                                    _BookingSegment.unassigned;
                                _selectedRange = AdminRangeFilter.all;
                              });
                            },
                          ),
                        _AdminTab.bookings => _BookingsAdminTab(
                            filteredBookings: filteredBookings,
                            branchBookings: branchBookings,
                            pendingRequests: pendingRequests,
                            branches: branches,
                            branchTechnicians: branchTechnicians,
                            allTechnicians: technicians,
                            allBookings: bookings,
                            now: now,
                            overdueBookings: overdueBookings,
                            dueSoonBookings: dueSoonBookings,
                            selectedSegment: _selectedBookingSegment,
                            controller: _searchController,
                            selectedStatus: _selectedStatus,
                            selectedTechnicianId: _selectedTechnicianId,
                            selectedRange: _selectedRange,
                            onSegmentChanged: (segment) => setState(
                              () => _selectedBookingSegment = segment,
                            ),
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
                        _AdminTab.attendance => _TechnicianWorkspaceSection(
                            performance: performance,
                            bookings: branchBookings,
                            locations: locations,
                            attendance: attendanceProviderValue,
                            attendanceLoading: attendanceAsync.isLoading,
                            now: now,
                          ),
                        _AdminTab.revenue => _RevenueAdminTab(
                            bills: bills,
                            bookings: branchBookings,
                            technicians: branchTechnicians,
                            branchName: effectiveBranch.name,
                            now: now,
                          ),
                        _AdminTab.monitoring => _LiveMonitoringSection(
                            locations: visibleLocations,
                            bookings: branchBookings,
                            technicians: branchTechnicians,
                            selectedTechnicianId: _selectedTechnicianId,
                            onTechnicianSelected: (technicianId) {
                              setState(() {
                                _selectedTechnicianId = technicianId;
                                _selectedAdminTab = _AdminTab.monitoring;
                              });
                            },
                            branchName: effectiveBranch.name,
                            branchCity: effectiveBranch.city,
                          ),
                      };
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(allBookingsProvider);
                          ref.invalidate(techniciansProvider);
                          ref.invalidate(allBillsProvider);
                          ref.invalidate(activeTechnicianLocationsProvider);
                        },
                        child: _AdminDashboardShell(
                          selected: _selectedAdminTab,
                          branches: branches,
                          activeBranch: effectiveBranch,
                          onTabSelected: (tab) =>
                              setState(() => _selectedAdminTab = tab),
                          onBranchSelected: (branch) =>
                              setState(() => _selectedBranchId = branch.id),
                          onAddBranch: () => _openBranchDialog(context, ref),
                          onEditBranch: (branch) =>
                              _openBranchDialog(context, ref, branch: branch),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _AdminContentHeader(
                                  title: _selectedAdminTab.label,
                                  branchName: effectiveBranch.name,
                                  onManualBooking: () =>
                                      _manualBooking(context, ref),
                                ),
                                const SizedBox(height: 20),
                                selectedTabContent,
                              ],
                            ),
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
                      validator: _realText,
                    ),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: _phoneValidator,
                    ),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      validator: _realText,
                    ),
                    TextFormField(
                      controller: appliance,
                      decoration: const InputDecoration(labelText: 'Appliance'),
                      validator: _realText,
                    ),
                    TextFormField(
                      controller: problem,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Problem description',
                      ),
                      validator: _realText,
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
                if (mounted) {
                  setState(() {
                    _selectedAdminTab = _AdminTab.bookings;
                    _selectedBookingSegment = _BookingSegment.unassigned;
                    _selectedBranchId = branch.id;
                    _selectedStatus = null;
                    _selectedTechnicianId = null;
                    _selectedRange = AdminRangeFilter.all;
                    _searchController.clear();
                  });
                }
                ref.invalidate(allBookingsProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Manual booking created for admin review.'),
                    ),
                  );
                }
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

  static String? _realText(String? value) {
    final required = _required(value);
    if (required != null) return required;
    final normalized = value!.trim().toLowerCase();
    final onlyRepeated = RegExp(r'^(.)\1{2,}$').hasMatch(normalized);
    if (onlyRepeated ||
        normalized == 'test' ||
        normalized == 'dummy' ||
        normalized == 'sample' ||
        normalized.contains('xxxx')) {
      return 'Enter real booking details';
    }
    return null;
  }

  static String? _phoneValidator(String? value) {
    final required = _required(value);
    if (required != null) return required;
    final digits = value!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || RegExp(r'^(.)\1{5,}$').hasMatch(digits)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  BranchInfo? _branchById(List<BranchInfo> branches, String? branchId) {
    if (branchId == null) return null;
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    return null;
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

class _AdminDashboardShell extends StatelessWidget {
  const _AdminDashboardShell({
    required this.selected,
    required this.branches,
    required this.activeBranch,
    required this.onTabSelected,
    required this.onBranchSelected,
    required this.onAddBranch,
    required this.onEditBranch,
    required this.child,
  });

  final _AdminTab selected;
  final List<BranchInfo> branches;
  final BranchInfo activeBranch;
  final ValueChanged<_AdminTab> onTabSelected;
  final ValueChanged<BranchInfo> onBranchSelected;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        if (compact) {
          return Column(
            children: [
              _AdminMobileNav(
                selected: selected,
                branches: branches,
                activeBranch: activeBranch,
                onTabSelected: onTabSelected,
                onBranchSelected: onBranchSelected,
                onAddBranch: onAddBranch,
                onEditBranch: onEditBranch,
              ),
              Expanded(child: child),
            ],
          );
        }
        return Row(
          children: [
            _AdminSidebar(
              selected: selected,
              branches: branches,
              activeBranch: activeBranch,
              onTabSelected: onTabSelected,
              onBranchSelected: onBranchSelected,
              onAddBranch: onAddBranch,
              onEditBranch: onEditBranch,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.selected,
    required this.branches,
    required this.activeBranch,
    required this.onTabSelected,
    required this.onBranchSelected,
    required this.onAddBranch,
    required this.onEditBranch,
  });

  final _AdminTab selected;
  final List<BranchInfo> branches;
  final BranchInfo activeBranch;
  final ValueChanged<_AdminTab> onTabSelected;
  final ValueChanged<BranchInfo> onBranchSelected;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 212,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FixNow',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Admin operations',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          for (final tab in _AdminTab.values) ...[
            _AdminNavItem(
              tab: tab,
              selected: selected == tab,
              onTap: () => onTabSelected(tab),
            ),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          _AdminBranchSwitcher(
            branches: branches,
            activeBranch: activeBranch,
            onBranchSelected: onBranchSelected,
            onAddBranch: onAddBranch,
            onEditBranch: onEditBranch,
          ),
        ],
      ),
    );
  }
}

class _AdminMobileNav extends StatelessWidget {
  const _AdminMobileNav({
    required this.selected,
    required this.branches,
    required this.activeBranch,
    required this.onTabSelected,
    required this.onBranchSelected,
    required this.onAddBranch,
    required this.onEditBranch,
  });

  final _AdminTab selected;
  final List<BranchInfo> branches;
  final BranchInfo activeBranch;
  final ValueChanged<_AdminTab> onTabSelected;
  final ValueChanged<BranchInfo> onBranchSelected;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'FixNow Admin',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _AdminBranchMenuButton(
                branches: branches,
                activeBranch: activeBranch,
                onBranchSelected: onBranchSelected,
                onAddBranch: onAddBranch,
                onEditBranch: onEditBranch,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in _AdminTab.values) ...[
                  _AdminMobileNavChip(
                    tab: tab,
                    selected: selected == tab,
                    onTap: () => onTabSelected(tab),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminNavItem extends StatelessWidget {
  const _AdminNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _AdminTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              tab.icon,
              size: 19,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 9),
            Text(
              tab.label,
              style: TextStyle(
                color: selected ? AppTheme.primary : AppTheme.textPrimary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMobileNavChip extends StatelessWidget {
  const _AdminMobileNavChip({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _AdminTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.1) : null,
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 17, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              tab.label,
              style: TextStyle(
                color: selected ? AppTheme.primary : AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminBranchSwitcher extends StatelessWidget {
  const _AdminBranchSwitcher({
    required this.branches,
    required this.activeBranch,
    required this.onBranchSelected,
    required this.onAddBranch,
    required this.onEditBranch,
  });

  final List<BranchInfo> branches;
  final BranchInfo activeBranch;
  final ValueChanged<BranchInfo> onBranchSelected;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current branch',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            activeBranch.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(activeBranch.radiusMeters / 1000).toStringAsFixed(0)} km radius',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _AdminBranchMenuButton(
            branches: branches,
            activeBranch: activeBranch,
            onBranchSelected: onBranchSelected,
            onAddBranch: onAddBranch,
            onEditBranch: onEditBranch,
          ),
        ],
      ),
    );
  }
}

class _AdminBranchMenuButton extends StatelessWidget {
  const _AdminBranchMenuButton({
    required this.branches,
    required this.activeBranch,
    required this.onBranchSelected,
    required this.onAddBranch,
    required this.onEditBranch,
  });

  final List<BranchInfo> branches;
  final BranchInfo activeBranch;
  final ValueChanged<BranchInfo> onBranchSelected;
  final VoidCallback onAddBranch;
  final ValueChanged<BranchInfo> onEditBranch;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Switch branch',
      onSelected: (value) {
        if (value == 'add') {
          onAddBranch();
        } else if (value == 'edit') {
          onEditBranch(activeBranch);
        } else if (value is BranchInfo) {
          onBranchSelected(value);
        }
      },
      itemBuilder: (context) => [
        for (final branch in branches)
          PopupMenuItem<Object>(
            value: branch,
            child: Row(
              children: [
                Icon(
                  branch.id == activeBranch.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: branch.id == activeBranch.id
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(branch.name)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'edit',
          child: Text('Edit current branch'),
        ),
        const PopupMenuItem<Object>(
          value: 'add',
          child: Text('Add branch'),
        ),
      ],
      child: const Text(
        'Switch branch',
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AdminContentHeader extends StatelessWidget {
  const _AdminContentHeader({
    required this.title,
    required this.branchName,
    required this.onManualBooking,
  });

  final String title;
  final String branchName;
  final VoidCallback onManualBooking;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              branchName,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: onManualBooking,
          icon: const Icon(Icons.add),
          label: const Text('Manual booking'),
        ),
      ],
    );
  }
}

class _OverviewAdminTab extends StatelessWidget {
  const _OverviewAdminTab({
    required this.activeTechnicians,
    required this.unassignedBookings,
    required this.overdueBookings,
    required this.jobsAtRisk,
    required this.idleTechnicians,
    required this.onReview,
  });

  final int activeTechnicians;
  final int unassignedBookings;
  final int overdueBookings;
  final int jobsAtRisk;
  final int idleTechnicians;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdminMetricGrid(
          metrics: [
            _MetricData(
              label: 'Active technicians',
              value: '$activeTechnicians',
              caption: 'Approved and active now',
              color: AppTheme.textPrimary,
              icon: Icons.engineering_outlined,
            ),
            _MetricData(
              label: 'Unassigned bookings',
              value: '$unassignedBookings',
              caption: 'Waiting for allocation',
              color: AppTheme.primary,
              icon: Icons.person_add_alt_1_outlined,
            ),
            _MetricData(
              label: 'Overdue jobs',
              value: '$overdueBookings',
              caption: 'Missed service window',
              color: const Color(0xFFD95C2A),
              icon: Icons.error_outline,
            ),
            _MetricData(
              label: 'Jobs at risk',
              value: '$jobsAtRisk',
              caption: '$idleTechnicians idle technician alert(s)',
              color: const Color(0xFFF08C00),
              icon: Icons.warning_amber_outlined,
            ),
          ],
        ),
        if (overdueBookings > 0 || idleTechnicians > 0) ...[
          const SizedBox(height: 20),
          _OverviewAlertBanner(
            overdueBookings: overdueBookings,
            idleTechnicians: idleTechnicians,
            onReview: onReview,
          ),
        ],
      ],
    );
  }
}

class _OverviewAlertBanner extends StatelessWidget {
  const _OverviewAlertBanner({
    required this.overdueBookings,
    required this.idleTechnicians,
    required this.onReview,
  });

  final int overdueBookings;
  final int idleTechnicians;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final critical = overdueBookings > 0;
    final color =
        critical ? const Color(0xFFD95C2A) : const Color(0xFFF08C00);
    final message = critical
        ? '$overdueBookings overdue job${overdueBookings == 1 ? '' : 's'} need review.'
        : '$idleTechnicians technician${idleTechnicians == 1 ? '' : 's'} may be idle or stale.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            critical ? Icons.error_outline : Icons.warning_amber_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onReview,
            child: const Text('Review'),
          ),
        ],
      ),
    );
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

class _AdminTabSelector extends StatelessWidget {
  const _AdminTabSelector({
    required this.selected,
    required this.onSelected,
  });

  final _AdminTab selected;
  final ValueChanged<_AdminTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tab in _AdminTab.values)
            ChoiceChip(
              avatar: Icon(tab.icon, size: 18),
              label: Text(tab.label),
              selected: selected == tab,
              onSelected: (_) => onSelected(tab),
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

class _BookingsAdminTab extends StatelessWidget {
  const _BookingsAdminTab({
    required this.filteredBookings,
    required this.branchBookings,
    required this.pendingRequests,
    required this.branches,
    required this.branchTechnicians,
    required this.allTechnicians,
    required this.allBookings,
    required this.now,
    required this.overdueBookings,
    required this.dueSoonBookings,
    required this.selectedSegment,
    required this.controller,
    required this.selectedStatus,
    required this.selectedTechnicianId,
    required this.selectedRange,
    required this.onSegmentChanged,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onTechnicianChanged,
    required this.onRangeChanged,
    required this.onClear,
  });

  final List<Booking> filteredBookings;
  final List<Booking> branchBookings;
  final List<AppUser> pendingRequests;
  final List<BranchInfo> branches;
  final List<AppUser> branchTechnicians;
  final List<AppUser> allTechnicians;
  final List<Booking> allBookings;
  final DateTime now;
  final List<Booking> overdueBookings;
  final int dueSoonBookings;
  final _BookingSegment selectedSegment;
  final TextEditingController controller;
  final BookingStatus? selectedStatus;
  final String? selectedTechnicianId;
  final AdminRangeFilter selectedRange;
  final ValueChanged<_BookingSegment> onSegmentChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<BookingStatus?> onStatusChanged;
  final ValueChanged<String?> onTechnicianChanged;
  final ValueChanged<AdminRangeFilter> onRangeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final unassigned = filteredBookings
        .where((booking) =>
            booking.status == BookingStatus.booked &&
            (booking.technicianId == null || booking.technicianId!.isEmpty))
        .toList();
    final held = filteredBookings
        .where((booking) => booking.status == BookingStatus.onHold)
        .toList();
    final closed = filteredBookings
        .where((booking) => booking.status == BookingStatus.closed)
        .toList();
    final ongoing = filteredBookings
        .where((booking) =>
            booking.status != BookingStatus.closed &&
            booking.status != BookingStatus.onHold &&
            !unassigned.contains(booking))
        .toList();
    final bookingsForSegment = switch (selectedSegment) {
      _BookingSegment.ongoing => ongoing,
      _BookingSegment.unassigned => unassigned,
      _BookingSegment.onHold => held,
      _BookingSegment.closed => closed,
    };
    final emptyText = switch (selectedSegment) {
      _BookingSegment.ongoing => 'No ongoing bookings',
      _BookingSegment.unassigned => 'No unassigned bookings',
      _BookingSegment.onHold => 'No bookings on hold',
      _BookingSegment.closed => 'No closed bookings',
    };

    return Column(
      children: [
        _AdminFilterPanel(
          controller: controller,
          selectedStatus: selectedStatus,
          selectedTechnicianId: selectedTechnicianId,
          selectedRange: selectedRange,
          technicians: branchTechnicians,
          onSearchChanged: onSearchChanged,
          onStatusChanged: onStatusChanged,
          onTechnicianChanged: onTechnicianChanged,
          onRangeChanged: onRangeChanged,
          onClear: onClear,
        ),
        if (pendingRequests.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PendingTechnicianSection(
            requests: pendingRequests,
            branches: branches,
          ),
        ],
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Booking control',
          subtitle:
              'Assign technicians, collect payments, and track service progress.',
          child: Column(
            children: [
              _BookingSegmentControl(
                selected: selectedSegment,
                counts: {
                  _BookingSegment.ongoing: ongoing.length,
                  _BookingSegment.unassigned: unassigned.length,
                  _BookingSegment.onHold: held.length,
                  _BookingSegment.closed: closed.length,
                },
                onSelected: onSegmentChanged,
              ),
              const SizedBox(height: 14),
              if (filteredBookings.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No bookings match the current filters.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else if (bookingsForSegment.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    emptyText,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < bookingsForSegment.length; i++) ...[
                      _AdminBookingCard(
                        booking: bookingsForSegment[i],
                        now: now,
                        branchTechnicians: branchTechnicians,
                        allTechnicians: allTechnicians,
                        allBookings: allBookings,
                      ),
                      if (i != bookingsForSegment.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookingSegmentControl extends StatelessWidget {
  const _BookingSegmentControl({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _BookingSegment selected;
  final Map<_BookingSegment, int> counts;
  final ValueChanged<_BookingSegment> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final segment in _BookingSegment.values) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(segment),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: selected == segment
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected == segment
                        ? AppTheme.primary
                        : AppTheme.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      segment.label,
                      style: TextStyle(
                        color: selected == segment
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 7),
                    _SegmentCountBadge(
                      count: counts[segment] ?? 0,
                      selected: selected == segment,
                    ),
                  ],
                ),
              ),
            ),
            if (segment != _BookingSegment.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SegmentCountBadge extends StatelessWidget {
  const _SegmentCountBadge({
    required this.count,
    required this.selected,
  });

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: selected ? Colors.white : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BookingGroupSection extends StatelessWidget {
  const _BookingGroupSection({
    required this.title,
    required this.emptyText,
    required this.bookings,
    required this.now,
    required this.branchTechnicians,
    required this.allTechnicians,
    required this.allBookings,
  });

  final String title;
  final String emptyText;
  final List<Booking> bookings;
  final DateTime now;
  final List<AppUser> branchTechnicians;
  final List<AppUser> allTechnicians;
  final List<Booking> allBookings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${bookings.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (bookings.isEmpty)
            _InlineEmptyState(
              icon: Icons.inbox_outlined,
              message: emptyText,
            )
          else
            Column(
              children: [
                for (var i = 0; i < bookings.length; i++) ...[
                  _AdminBookingCard(
                    booking: bookings[i],
                    now: now,
                    branchTechnicians: branchTechnicians,
                    allTechnicians: allTechnicians,
                    allBookings: allBookings,
                  ),
                  if (i != bookings.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RevenueAdminTab extends StatelessWidget {
  const _RevenueAdminTab({
    required this.bills,
    required this.bookings,
    required this.technicians,
    required this.branchName,
    required this.now,
  });

  final List<Bill> bills;
  final List<Booking> bookings;
  final List<AppUser> technicians;
  final String branchName;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final branchBookingIds = {for (final booking in bookings) booking.id};
    final branchTechnicianIds = {
      for (final technician in technicians) technician.uid,
    };
    final branchBills = bills.where((bill) {
      return branchBookingIds.contains(bill.bookingId) ||
          branchTechnicianIds.contains(bill.technicianId);
    }).toList();
    final paidBills = branchBills.where((bill) => bill.isPaid).toList();
    final confirmationBills =
        branchBills.where((bill) => bill.hasPaymentForApproval).toList();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final todayRevenue = _sumBills(
      paidBills.where((bill) => isSameDay(bill.createdAt, now)),
    );
    final weekRevenue = _sumBills(
      paidBills.where((bill) =>
          bill.createdAt.isAfter(weekStart) ||
          isSameDay(bill.createdAt, weekStart)),
    );
    final monthRevenue = _sumBills(
      paidBills.where((bill) =>
          bill.createdAt.year == now.year && bill.createdAt.month == now.month),
    );
    return Column(
      children: [
        _AdminMetricGrid(
          metrics: [
            _MetricData(
              label: 'Today',
              value: _formatCurrency(todayRevenue),
              caption: 'Paid collections',
              color: AppTheme.primary,
              icon: Icons.today_outlined,
            ),
            _MetricData(
              label: 'This week',
              value: _formatCurrency(weekRevenue),
              caption: 'Week-to-date revenue',
              color: AppTheme.accent,
              icon: Icons.date_range_outlined,
            ),
            _MetricData(
              label: 'This month',
              value: _formatCurrency(monthRevenue),
              caption: DateFormat('MMMM yyyy').format(now),
              color: AppTheme.primary,
              icon: Icons.insights_outlined,
            ),
            _MetricData(
              label: 'Pending confirm',
              value: '${confirmationBills.length}',
              caption: _formatCurrency(_sumBills(confirmationBills)),
              color: const Color(0xFFD95C2A),
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Branch revenue',
          subtitle: '$branchName paid and pending collection report.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniStat(label: 'Paid bills', value: '${paidBills.length}'),
              _MiniStat(
                label: 'Awaiting technician',
                value: '${confirmationBills.length}',
              ),
              _MiniStat(
                label: 'Uncollected bills',
                value:
                    '${branchBills.where((bill) => !bill.isPaid && !bill.hasPaymentForApproval).length}',
              ),
              _MiniStat(
                label: 'All-time paid',
                value: _formatCurrency(_sumBills(paidBills)),
              ),
              _MiniStat(
                label: 'Closed orders',
                value:
                    '${bookings.where((booking) => booking.status == BookingStatus.closed).length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Technician-wise revenue',
          subtitle: 'Paid collections and pending bills by technician.',
          child: technicians.isEmpty
              ? const _InlineEmptyState(
                  icon: Icons.engineering_outlined,
                  message: 'No technicians are approved for this branch yet.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < technicians.length; i++) ...[
                      _RevenueTechnicianRow(
                        technician: technicians[i],
                        bills: branchBills
                            .where((bill) =>
                                bill.technicianId == technicians[i].uid)
                            .toList(),
                        now: now,
                      ),
                      if (i != technicians.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static double _sumBills(Iterable<Bill> bills) =>
      bills.fold<double>(0, (sum, bill) => sum + bill.amount);
}

class _RevenueTechnicianRow extends StatelessWidget {
  const _RevenueTechnicianRow({
    required this.technician,
    required this.bills,
    required this.now,
  });

  final AppUser technician;
  final List<Bill> bills;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final paidBills = bills.where((bill) => bill.isPaid).toList();
    final today = _sumBills(
      paidBills.where((bill) => isSameDay(bill.createdAt, now)),
    );
    final month = _sumBills(
      paidBills.where((bill) =>
          bill.createdAt.year == now.year && bill.createdAt.month == now.month),
    );
    final pending = _sumBills(bills.where((bill) => !bill.isPaid));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            foregroundColor: AppTheme.primary,
            child: Text(
              _registeredTechnicianName(technician)
                  .substring(0, 1)
                  .toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _registeredTechnicianName(technician),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${paidBills.length} paid bill(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniStat(label: 'Today', value: _formatCurrency(today)),
              _MiniStat(label: 'Month', value: _formatCurrency(month)),
              _MiniStat(label: 'Pending', value: _formatCurrency(pending)),
            ],
          ),
        ],
      ),
    );
  }

  static double _sumBills(Iterable<Bill> bills) =>
      bills.fold<double>(0, (sum, bill) => sum + bill.amount);
}

class _LiveMonitoringSection extends StatelessWidget {
  const _LiveMonitoringSection({
    required this.locations,
    required this.bookings,
    required this.technicians,
    required this.selectedTechnicianId,
    required this.onTechnicianSelected,
    required this.branchName,
    required this.branchCity,
  });

  final List<TechnicianLocation> locations;
  final List<Booking> bookings;
  final List<AppUser> technicians;
  final String? selectedTechnicianId;
  final ValueChanged<String?> onTechnicianSelected;
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
    final technicianById = {
      for (final technician in technicians) technician.uid: technician,
    };
    final locationsByTechnician = {
      for (final location in locations) location.technicianId: location,
    };
    final now = DateTime.now();
    final idleTechnicians = technicians.where((technician) {
      final booking = activeByTechnician[technician.uid];
      if (booking == null || booking.status != BookingStatus.onTheWay) {
        return false;
      }
      final location = locationsByTechnician[technician.uid];
      return location == null ||
          !location.isOnline ||
          now.difference(location.updatedAt) > _idleTechnicianThreshold;
    }).toList();

    return _SectionCard(
      title: 'Live monitoring',
      subtitle:
          'Watch all technicians at once and cross-check who is moving, idle, or overdue.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                color: AppTheme.primary,
              ),
              _MonitorChip(
                label: 'Stale updates',
                value:
                    '${visibleLocations.where((location) => now.difference(location.updatedAt) > _idleTechnicianThreshold).length}',
                color: const Color(0xFFD95C2A),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (idleTechnicians.isNotEmpty) ...[
            _IdleTechnicianAlerts(
              technicians: idleTechnicians,
              activeByTechnician: activeByTechnician,
              locationsByTechnician: locationsByTechnician,
              onTrack: onTechnicianSelected,
            ),
            const SizedBox(height: 16),
          ],
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
                    technicianById: technicianById,
                  ),
          ),
          const SizedBox(height: 16),
          if (technicians.isEmpty)
            const _InlineEmptyState(
              icon: Icons.engineering_outlined,
              message: 'No approved technicians in this branch.',
            )
          else
            _TechnicianDirectory(
              technicians: technicians,
              selectedTechnicianId: selectedTechnicianId,
              activeByTechnician: activeByTechnician,
              locationsByTechnician: locationsByTechnician,
              onTrack: onTechnicianSelected,
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

class _TechnicianDirectory extends StatelessWidget {
  const _TechnicianDirectory({
    required this.technicians,
    required this.selectedTechnicianId,
    required this.activeByTechnician,
    required this.locationsByTechnician,
    required this.onTrack,
  });

  final List<AppUser> technicians;
  final String? selectedTechnicianId;
  final Map<String, Booking> activeByTechnician;
  final Map<String, TechnicianLocation> locationsByTechnician;
  final ValueChanged<String?> onTrack;

  @override
  Widget build(BuildContext context) {
    String? selectedName;
    if (selectedTechnicianId != null) {
      for (final technician in technicians) {
        if (technician.uid == selectedTechnicianId) {
          selectedName = _registeredTechnicianName(technician);
          break;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Technician directory',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selectedName == null
                        ? '${technicians.length} technicians listed'
                        : 'Tracking $selectedName',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedTechnicianId != null)
              TextButton.icon(
                onPressed: () => onTrack(null),
                icon: const Icon(Icons.layers_outlined),
                label: const Text('Show all'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: technicians.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final technician = technicians[index];
              return _TechnicianTrackingTile(
                technician: technician,
                location: locationsByTechnician[technician.uid],
                booking: activeByTechnician[technician.uid],
                selected: selectedTechnicianId == technician.uid,
                onTrack: () => onTrack(technician.uid),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IdleTechnicianAlerts extends StatelessWidget {
  const _IdleTechnicianAlerts({
    required this.technicians,
    required this.activeByTechnician,
    required this.locationsByTechnician,
    required this.onTrack,
  });

  final List<AppUser> technicians;
  final Map<String, Booking> activeByTechnician;
  final Map<String, TechnicianLocation> locationsByTechnician;
  final ValueChanged<String?> onTrack;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFD95C2A);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${technicians.length} idle technician alert${technicians.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final technician in technicians) ...[
            _IdleTechnicianAlertRow(
              technician: technician,
              booking: activeByTechnician[technician.uid],
              location: locationsByTechnician[technician.uid],
              onTrack: () => onTrack(technician.uid),
            ),
            if (technician != technicians.last)
              Divider(height: 14, color: color.withValues(alpha: 0.18)),
          ],
        ],
      ),
    );
  }
}

class _IdleTechnicianAlertRow extends StatelessWidget {
  const _IdleTechnicianAlertRow({
    required this.technician,
    required this.booking,
    required this.location,
    required this.onTrack,
  });

  final AppUser technician;
  final Booking? booking;
  final TechnicianLocation? location;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final reason = location == null
        ? 'No live location shared'
        : !location!.isOnline
            ? 'Technician is offline'
            : 'No GPS update for ${_formatRelative(location!.updatedAt)}';
    final jobLabel = booking == null
        ? 'Active job not found'
        : '${booking!.applianceType} for ${booking!.customerName}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFFFE2D8),
          foregroundColor: Color(0xFFD95C2A),
          child: Icon(Icons.report_problem_outlined, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _registeredTechnicianName(technician),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                jobLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                reason,
                style: const TextStyle(
                  color: Color(0xFFD95C2A),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: location == null ? null : onTrack,
          icon: const Icon(Icons.my_location_outlined, size: 16),
          label: const Text('Track'),
        ),
      ],
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
    required this.now,
  });

  final List<TechnicianPerformance> performance;
  final List<Booking> bookings;
  final List<TechnicianLocation> locations;
  final List<Attendance> attendance;
  final bool attendanceLoading;
  final DateTime now;

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
    final monthAttendance = attendance
        .where((record) =>
            record.timestamp.year == now.year &&
            record.timestamp.month == now.month)
        .toList();
    final faceIdIssues =
        monthAttendance.where((record) => !record.faceMatchPassed).length;

    return _SectionCard(
      title: 'Attendance report',
      subtitle:
          'Monthly technician sheets with punch-in time, selfie, availability, and Face ID status.',
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
                label: DateFormat('MMM yyyy').format(now),
                value: '${monthAttendance.length} punch-in(s)',
              ),
              _MiniStat(label: 'Face ID issues', value: '$faceIdIssues'),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 3
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                final spacing = 12.0;
                final cardWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final item in performance)
                      SizedBox(
                        width: cardWidth,
                        child: _AttendanceTechnicianCard(
                          item: item,
                          records:
                              attendanceByTechnician[item.technician.uid] ??
                                  const [],
                          location: locationByTechnician[item.technician.uid],
                          activeBookings:
                              activeBookingsByTechnician[item.technician.uid] ??
                                  const [],
                          now: now,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AttendanceTechnicianCard extends ConsumerWidget {
  const _AttendanceTechnicianCard({
    required this.item,
    required this.records,
    required this.location,
    required this.activeBookings,
    required this.now,
  });

  final TechnicianPerformance item;
  final List<Attendance> records;
  final TechnicianLocation? location;
  final List<Booking> activeBookings;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technician = item.technician;
    final sortedRecords = [...records]
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final latest = sortedRecords.isEmpty ? null : sortedRecords.first;
    final todayRecord = _attendanceForDay(sortedRecords, now);
    final todayStatus = todayRecord?.status ?? 'not_marked';
    final monthRecords = sortedRecords
        .where((record) =>
            record.timestamp.year == now.year &&
            record.timestamp.month == now.month)
        .toList();
    final faceIssueCount =
        monthRecords.where((record) => !record.faceMatchPassed).length;
    final availabilityColor =
        technician.isActive ? AppTheme.accent : const Color(0xFFD95C2A);
    final locationText = location == null
        ? 'No live location'
        : 'Location ${_formatRelative(location!.updatedAt)}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => _AttendanceDetailDialog(
            technician: technician,
            records: sortedRecords,
            activeBookings: activeBookings,
            now: now,
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: availabilityColor.withValues(alpha: 0.12),
                    foregroundColor: availabilityColor,
                    child: Text(
                      _registeredTechnicianName(technician)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _registeredTechnicianName(technician),
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
              const SizedBox(height: 12),
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
                    label: '${monthRecords.length} this month',
                    color: AppTheme.accent,
                  ),
                  _StatusPill(
                    label: '$faceIssueCount Face ID issue(s)',
                    color: faceIssueCount > 0
                        ? const Color(0xFFD95C2A)
                        : AppTheme.accent,
                  ),
                  _StatusPill(
                    label: 'Today ${_adminAttendanceStatusLabel(todayStatus)}',
                    color: _adminAttendanceStatusColor(todayStatus),
                  ),
                  _StatusPill(
                    label: latest == null
                        ? 'No punch-in yet'
                        : 'Latest ${DateFormat('dd MMM, hh:mm a').format(latest.timestamp)}',
                    color: latest == null
                        ? const Color(0xFFD95C2A)
                        : AppTheme.textSecondary,
                  ),
                  _StatusPill(
                    label: latest?.selfieUrl.trim().isNotEmpty == true
                        ? 'Selfie received'
                        : 'Selfie missing',
                    color: latest?.selfieUrl.trim().isNotEmpty == true
                        ? AppTheme.primary
                        : const Color(0xFFD95C2A),
                  ),
                  _StatusPill(
                    label: locationText,
                    color: item.highlightRisk
                        ? const Color(0xFFD95C2A)
                        : AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Open monthly sheet',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceDetailDialog extends ConsumerWidget {
  const _AttendanceDetailDialog({
    required this.technician,
    required this.records,
    required this.activeBookings,
    required this.now,
  });

  final AppUser technician;
  final List<Attendance> records;
  final List<Booking> activeBookings;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthEntries = _monthAttendanceEntries(records, now);
    final monthRecords = monthEntries
        .where((entry) => entry.record != null)
        .map((entry) => entry.record!)
        .toList();
    final notMarked = monthEntries.where((entry) => entry.record == null).length;

    return AlertDialog(
      title: Text('${_registeredTechnicianName(technician)} attendance'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniStat(
                    label: 'Sheet',
                    value: DateFormat('MMMM yyyy').format(now),
                  ),
                  _MiniStat(
                    label: 'Punch-ins',
                    value: '${monthRecords.length}',
                  ),
                  _MiniStat(
                    label: 'Not marked',
                    value: '$notMarked',
                  ),
                  _MiniStat(
                    label: 'Active jobs',
                    value: '${activeBookings.length}',
                  ),
                  _MiniStat(
                    label: 'Face ID issues',
                    value:
                        '${monthRecords.where((item) => !item.faceMatchPassed).length}',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (monthEntries.isEmpty)
                const _InlineEmptyState(
                  icon: Icons.event_busy_outlined,
                  message: 'No attendance marked for this month.',
                )
              else
                Column(
                  children: [
                    const _AttendanceSheetHeader(),
                    for (final entry in monthEntries)
                      _AttendanceSheetRow(
                        technician: technician,
                        entry: entry,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AttendanceSheetHeader extends StatelessWidget {
  const _AttendanceSheetHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Date', style: _sheetHeaderStyle)),
          Expanded(flex: 2, child: Text('Punch in', style: _sheetHeaderStyle)),
          Expanded(flex: 2, child: Text('Selfie', style: _sheetHeaderStyle)),
          Expanded(
              flex: 2,
              child: Text('Status / Face ID', style: _sheetHeaderStyle)),
          Expanded(flex: 2, child: Text('Admin action', style: _sheetHeaderStyle)),
        ],
      ),
    );
  }
}

class _AttendanceSheetRow extends ConsumerWidget {
  const _AttendanceSheetRow({
    required this.technician,
    required this.entry,
  });

  final AppUser technician;
  final _AttendanceDayEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = entry.record;
    final hasSelfie = record?.selfieUrl.trim().isNotEmpty == true;
    final status = record?.status ?? 'not_marked';
    final statusColor = _adminAttendanceStatusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(DateFormat('dd MMM yyyy').format(entry.day)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              record == null
                  ? '-'
                  : DateFormat('hh:mm a').format(record.timestamp),
            ),
          ),
          Expanded(
            flex: 2,
            child: hasSelfie && record != null
                ? TextButton.icon(
                    onPressed: () => _openSelfieDialog(context, record),
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('View selfie'),
                  )
                : const Text('Not received'),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _adminAttendanceStatusLabel(status),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
                if (record != null)
                  Text(
                    record.markedBy == 'admin'
                        ? 'Admin: ${record.adminOverrideReason ?? 'Override'}'
                        : record.faceMatchPassed
                            ? 'Face matched'
                            : 'Face not matched',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: TextButton.icon(
              onPressed: () => _openAdminOverrideDialog(context, ref),
              icon: const Icon(Icons.edit_calendar_outlined, size: 16),
              label: const Text('Override'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdminOverrideDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var status = 'present';
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(
              'Override ${DateFormat('dd MMM yyyy').format(entry.day)}',
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Attendance status',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'present', child: Text('Present')),
                      DropdownMenuItem(
                        value: 'late',
                        child: Text('Late allowed'),
                      ),
                      DropdownMenuItem(value: 'absent', child: Text('Absent')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => status = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Example: medical emergency, network issue',
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Reason is required'
                            : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final admin = ref.read(currentUserProvider).valueOrNull;
                  if (admin == null) return;
                  await ref
                      .read(technicianRepositoryProvider)
                      .adminOverrideAttendance(
                        technicianId: technician.uid,
                        day: entry.day,
                        status: status,
                        adminId: admin.uid,
                        reason: reason.text,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      reason.dispose();
    }
  }

  void _openSelfieDialog(BuildContext context, Attendance record) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Selfie - ${DateFormat('dd MMM, hh:mm a').format(record.timestamp)}',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Image.network(
            record.selfieUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Text('Selfie could not be previewed.'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _AttendanceDayEntry {
  const _AttendanceDayEntry({
    required this.day,
    required this.record,
  });

  final DateTime day;
  final Attendance? record;
}

List<_AttendanceDayEntry> _monthAttendanceEntries(
  List<Attendance> records,
  DateTime now,
) {
  final recordsByDay = {
    for (final record in records)
      if (record.timestamp.year == now.year &&
          record.timestamp.month == now.month)
        _attendanceDayKey(record.timestamp): record,
  };
  return [
    for (var day = now.day; day >= 1; day--)
      _AttendanceDayEntry(
        day: DateTime(now.year, now.month, day),
        record: recordsByDay[_attendanceDayKey(
          DateTime(now.year, now.month, day),
        )],
      ),
  ];
}

Attendance? _attendanceForDay(List<Attendance> records, DateTime day) {
  final key = _attendanceDayKey(day);
  for (final record in records) {
    if (_attendanceDayKey(record.timestamp) == key) return record;
  }
  return null;
}

String _attendanceDayKey(DateTime day) {
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

String _adminAttendanceStatusLabel(String status) {
  return switch (status) {
    'present' => 'Present',
    'late' => 'Late',
    'face_failed' => 'Face failed',
    'absent' => 'Absent',
    'not_marked' => 'Not marked',
    _ => status.isEmpty ? 'Not marked' : status,
  };
}

Color _adminAttendanceStatusColor(String status) {
  return switch (status) {
    'present' => AppTheme.accent,
    'late' => const Color(0xFFF08C00),
    'face_failed' => const Color(0xFFD95C2A),
    'absent' => const Color(0xFFD95C2A),
    'not_marked' => const Color(0xFFD95C2A),
    _ => AppTheme.textSecondary,
  };
}

const _sheetHeaderStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w900,
  color: AppTheme.textSecondary,
);

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
      if (technicianId == null || !isTechnicianBusyStatus(item.status)) {
        continue;
      }
      activeLoad[technicianId] = (activeLoad[technicianId] ?? 0) + 1;
    }
    final branchRoster = branchTechnicians.isEmpty
        ? allTechnicians
        : branchTechnicians;
    final hasApprovedTechnician = branchRoster.any(
      (tech) => tech.accountStatus == AccountStatus.approved,
    );
    final hasPendingTechnician = branchRoster.any(
      (tech) => tech.accountStatus == AccountStatus.pendingApproval,
    );
    final hasInactiveTechnician = branchRoster.any(
      (tech) =>
          tech.accountStatus == AccountStatus.approved && !tech.isActive,
    );
    final technicians = branchRoster
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
    final canAssignTechnician =
        booking.status == BookingStatus.booked && booking.technicianId == null;
    final canResumeHeldBooking = booking.status == BookingStatus.onHold;
    final canChangeTechnician = canAssignTechnician || canResumeHeldBooking;
    final assignableTechnicians = technicians.where((tech) {
      if (canChangeTechnician) return true;
      return tech.uid == booking.technicianId;
    }).toList();
    final bill = ref.watch(bookingBillProvider(booking.id)).valueOrNull;
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
                      : bill.hasPaymentForApproval
                          ? Icons.verified_outlined
                          : Icons.currency_rupee,
                  label:
                      '${bill.paymentStatusLabel} ${_formatCurrency(bill.amount)}',
                ),
              if (bill != null &&
                  (bill.isPaid || bill.hasPaymentForApproval) &&
                  bill.paymentMode != null)
                _BookingInfoChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: bill.paymentModeLabel,
                ),
              if (booking.status == BookingStatus.onHold &&
                  booking.holdReason != null &&
                  booking.holdReason!.isNotEmpty)
                _BookingInfoChip(
                  icon: Icons.pause_circle_outline,
                  label: 'Hold: ${booking.holdReason}',
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (assignableTechnicians.isEmpty && canChangeTechnician) ...[
            _AssignmentEmptyState(
              message: _assignmentEmptyMessage(
                hasApprovedTechnician: hasApprovedTechnician,
                hasPendingTechnician: hasPendingTechnician,
                hasInactiveTechnician: hasInactiveTechnician,
                activeTechnicianCount: technicians.length,
                canChangeTechnician: canChangeTechnician,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                if (assignableTechnicians.isNotEmpty)
                  _TechnicianPickerButton(
                    label: booking.technicianId == null
                        ? 'Assign technician'
                        : canResumeHeldBooking
                            ? 'Resume with technician'
                            : 'Reassign technician',
                    enabled: canChangeTechnician,
                    onPressed: () => _showTechnicianPicker(
                      context: context,
                      ref: ref,
                      technicians: assignableTechnicians,
                      locationByTechnician: locationByTechnician,
                      branchTechnicianIds: branchTechnicianIds,
                      activeLoad: activeLoad,
                    ),
                  ),
                if (booking.status == BookingStatus.onHold &&
                    booking.technicianId != null)
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await ref
                            .read(bookingRepositoryProvider)
                            .resumeFromHold(bookingId: booking.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Booking resumed.'),
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
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Resume booking'),
                  ),
                if (_canPlaceOnHold(booking.status))
                  OutlinedButton.icon(
                    onPressed: () => _showHoldDialog(context, ref),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Place on hold'),
                  ),
                FilledButton.icon(
                  onPressed: () => context.push('/booking/${booking.id}'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
              ],
            ),
          ),
          if (bill != null && bill.hasPaymentForApproval) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerRight,
              child: _StatusPill(
                label: 'Waiting for technician confirmation',
                color: Color(0xFFD95C2A),
              ),
            ),
          ] else if (bill != null && !bill.isPaid) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerRight,
              child: _StatusPill(
                label: 'Waiting for technician payment entry',
                color: Color(0xFFD95C2A),
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
    final load = activeJobs == 0
        ? 'free now'
        : '$activeJobs active job${activeJobs == 1 ? '' : 's'}';
    if (distance.isInfinite) {
      return '${technician.name} - $priority - $load - location unavailable';
    }
    return '${technician.name} - $priority - $load - ${(distance / 1000).toStringAsFixed(1)} km';
  }

  static String _technicianDropdownLabel(AppUser technician, int activeJobs) {
    final name = _registeredTechnicianName(technician);
    if (activeJobs == 0) return '$name - free now';
    return '$name - busy, $activeJobs active job${activeJobs == 1 ? '' : 's'} - assign anyway';
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

  static String _assignmentEmptyMessage({
    required bool hasApprovedTechnician,
    required bool hasPendingTechnician,
    required bool hasInactiveTechnician,
    required int activeTechnicianCount,
    required bool canChangeTechnician,
  }) {
    if (!canChangeTechnician) {
      return 'This booking cannot be reassigned in the current status. Place it on hold before changing technician.';
    }
    if (!hasApprovedTechnician && hasPendingTechnician) {
      return 'A technician is waiting for approval in this branch. Approve the technician request first, then assign this booking.';
    }
    if (hasInactiveTechnician) {
      return 'Approved technicians in this branch are inactive. Switch one technician to Available, then assign this booking.';
    }
    return 'No approved technicians are active in this branch. Once a technician is active, admin can assign them even if they already have another job.';
  }

  static bool _canPlaceOnHold(BookingStatus status) {
    return status != BookingStatus.booked &&
        status != BookingStatus.onHold &&
        status != BookingStatus.serviceCompleted &&
        status != BookingStatus.billGenerated &&
        status != BookingStatus.closed;
  }

  Future<void> _showHoldDialog(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Place booking on hold'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: reason,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Hold reason',
                hintText: 'Example: AC board taken to service center',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(bookingRepositoryProvider).placeOnHold(
                        bookingId: booking.id,
                        reason: reason.text,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Booking placed on hold. Technician is now available.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(error.toString()),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Hold booking'),
            ),
          ],
        ),
      );
    } finally {
      reason.dispose();
    }
  }

  Future<void> _assignTechnician({
    required BuildContext context,
    required WidgetRef ref,
    required AppUser technician,
    required TechnicianLocation? location,
    required int activeJobs,
  }) async {
    final confirmed = await _showAssignmentConfirmation(
      context: context,
      technician: technician,
      location: location,
      activeJobs: activeJobs,
    );
    if (!confirmed || !context.mounted) return;
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

  Future<void> _showTechnicianPicker({
    required BuildContext context,
    required WidgetRef ref,
    required List<AppUser> technicians,
    required Map<String, TechnicianLocation> locationByTechnician,
    required Set<String> branchTechnicianIds,
    required Map<String, int> activeLoad,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose technician',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Busy technicians can still be assigned after confirmation.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: technicians.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final technician = technicians[index];
                        final location = locationByTechnician[technician.uid];
                        final activeJobs = activeLoad[technician.uid] ?? 0;
                        final distance = _distanceToBooking(booking, location);
                        final distanceLabel = distance.isInfinite
                            ? 'Distance unavailable'
                            : '${(distance / 1000).toStringAsFixed(1)} km away';
                        return _TechnicianPickerRow(
                          technician: technician,
                          activeJobs: activeJobs,
                          distanceLabel: distanceLabel,
                          branchPriority:
                              branchTechnicianIds.contains(technician.uid),
                          onSelect: () {
                            Navigator.pop(sheetContext);
                            _assignTechnician(
                              context: context,
                              ref: ref,
                              technician: technician,
                              location: location,
                              activeJobs: activeJobs,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showAssignmentConfirmation({
    required BuildContext context,
    required AppUser technician,
    required TechnicianLocation? location,
    required int activeJobs,
  }) async {
    var isAssigning = false;
    final distance = _distanceToBooking(booking, location);
    final distanceLabel = distance.isInfinite
        ? 'Technician live location unavailable'
        : '${(distance / 1000).toStringAsFixed(1)} km from service location';
    final loadLabel = activeJobs == 0
        ? 'No active jobs'
        : '$activeJobs active job${activeJobs == 1 ? '' : 's'}';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Confirm technician assignment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AssignmentConfirmRow(
                    icon: Icons.engineering_outlined,
                    label: 'Technician',
                    value: _registeredTechnicianName(technician),
                  ),
                  _AssignmentConfirmRow(
                    icon: Icons.work_outline,
                    label: 'Current load',
                    value: loadLabel,
                  ),
                  _AssignmentConfirmRow(
                    icon: Icons.near_me_outlined,
                    label: 'Distance',
                    value: distanceLabel,
                  ),
                  _AssignmentConfirmRow(
                    icon: Icons.home_repair_service_outlined,
                    label: 'Booking',
                    value:
                        '${booking.applianceType} for ${booking.customerName}',
                  ),
                  _AssignmentConfirmRow(
                    icon: Icons.event_outlined,
                    label: 'Schedule',
                    value:
                        '${DateFormat('dd MMM yyyy').format(booking.preferredDate)} at ${booking.preferredTime}',
                  ),
                  if (booking.address.trim().isNotEmpty)
                    _AssignmentConfirmRow(
                      icon: Icons.location_on_outlined,
                      label: 'Service address',
                      value: booking.address,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isAssigning
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isAssigning
                      ? null
                      : () async {
                          setDialogState(() => isAssigning = true);
                          Navigator.of(dialogContext).pop(true);
                        },
                  icon: isAssigning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_turned_in_outlined),
                  label: Text(isAssigning ? 'Assigning...' : 'Assign'),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }
}

class _AssignmentConfirmRow extends StatelessWidget {
  const _AssignmentConfirmRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
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

class _TechnicianPickerButton extends StatelessWidget {
  const _TechnicianPickerButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.engineering_outlined),
      label: Text(label),
    );
  }
}

class _TechnicianPickerRow extends StatelessWidget {
  const _TechnicianPickerRow({
    required this.technician,
    required this.activeJobs,
    required this.distanceLabel,
    required this.branchPriority,
    required this.onSelect,
  });

  final AppUser technician;
  final int activeJobs;
  final String distanceLabel;
  final bool branchPriority;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final busy = activeJobs > 0;
    final statusColor =
        busy ? const Color(0xFFF08C00) : const Color(0xFF2B8A3E);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              foregroundColor: AppTheme.primary,
              child: Text(
                _registeredTechnicianName(technician)
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _registeredTechnicianName(technician),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      distanceLabel,
                      if (branchPriority) 'Branch priority',
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                busy
                    ? 'Busy · $activeJobs active'
                    : 'Free',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
  const _AssignmentEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD88A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.engineering_outlined, color: Color(0xFFD78200)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
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
    required this.technicianById,
  });

  final List<TechnicianLocation> locations;
  final Map<String, Booking> activeByTechnician;
  final Map<String, AppUser> technicianById;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final points = locations.map((location) {
      final booking = activeByTechnician[location.technicianId];
      final stale =
          now.difference(location.updatedAt) > _idleTechnicianThreshold;
      final color = stale
          ? const Color(0xFFD95C2A)
          : booking != null
              ? AppTheme.primary
              : AppTheme.accent;
      return GoogleMapPoint(
        latitude: location.latitude,
        longitude: location.longitude,
        label: _technicianInitial(technicianById[location.technicianId]),
        color: color,
        icon: booking == null
            ? Icons.engineering_outlined
            : Icons.delivery_dining_outlined,
        bearing: location.bearing,
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: InAppLiveMap(
        points: points,
        zoom: points.isEmpty ? 4 : 11,
        badge: 'All technicians live',
      ),
    );
  }
}

String _technicianInitial(AppUser? technician) {
  if (technician == null) return 'T';
  return _registeredTechnicianName(technician).substring(0, 1).toUpperCase();
}

class _TechnicianTrackingTile extends StatelessWidget {
  const _TechnicianTrackingTile({
    required this.technician,
    required this.location,
    required this.booking,
    required this.selected,
    required this.onTrack,
  });

  final AppUser technician;
  final TechnicianLocation? location;
  final Booking? booking;
  final bool selected;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale = location == null ||
        now.difference(location!.updatedAt) > _idleTechnicianThreshold;
    final hasActiveJob = booking != null;
    final statusColor = stale
        ? const Color(0xFFD95C2A)
        : hasActiveJob
            ? AppTheme.primary
            : AppTheme.accent;
    final statusLabel = location == null
        ? 'No location shared'
        : stale
            ? 'Location stale'
            : hasActiveJob
                ? 'On active job'
                : 'Available on map';
    final techPoint = location == null
        ? null
        : GoogleMapPoint(
            latitude: location!.latitude,
            longitude: location!.longitude,
            label: 'T',
            color: AppTheme.primary,
            icon: Icons.engineering_outlined,
            bearing: location!.bearing,
          );
    final customerPoint =
        booking?.latitude == null || booking?.longitude == null
            ? null
            : GoogleMapPoint(
                latitude: booking!.latitude!,
                longitude: booking!.longitude!,
                label: 'C',
                color: AppTheme.accent,
                icon: Icons.home_repair_service_outlined,
              );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppTheme.primary : AppTheme.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                foregroundColor: statusColor,
                child: const Icon(Icons.engineering_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _registeredTechnicianName(technician),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      booking == null
                          ? statusLabel
                          : '$statusLabel - ${booking!.applianceType} for ${booking!.customerName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (location != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${location!.isOnline ? 'Online' : 'Offline'} - '
                        '${_formatSpeed(location!.speed)} - '
                        'Updated ${_formatRelative(location!.updatedAt)}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: location == null ? null : onTrack,
                icon: const Icon(Icons.my_location_outlined, size: 17),
                label: const Text('Track'),
              ),
            ],
          ),
          if (selected && techPoint != null && customerPoint != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 190,
                child: RoadRouteMap(
                  points: [techPoint, customerPoint],
                  origin: techPoint,
                  destination: customerPoint,
                  zoom: 12,
                  badge: 'Technician route',
                ),
              ),
            ),
          ],
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
    BookingStatus.booked => AppTheme.primary,
    BookingStatus.technicianAssigned => AppTheme.accent,
    BookingStatus.accepted => const Color(0xFF14A38B),
    BookingStatus.onTheWay => const Color(0xFF0088CC),
    BookingStatus.arrived => AppTheme.primary,
    BookingStatus.customerConfirmedArrival => const Color(0xFF2B8A3E),
    BookingStatus.estimateSent => const Color(0xFFF08C00),
    BookingStatus.estimateRejected => const Color(0xFFD95C2A),
    BookingStatus.estimateApproved => const Color(0xFF2B8A3E),
    BookingStatus.serviceStarted => const Color(0xFF7B61FF),
    BookingStatus.onHold => const Color(0xFF845EF7),
    BookingStatus.serviceCompleted => AppTheme.accentDark,
    BookingStatus.billGenerated => const Color(0xFF845EF7),
    BookingStatus.closed => const Color(0xFF6C757D),
  };
}

String _formatCurrency(double amount) {
  return 'Rs. ${amount.toStringAsFixed(0)}';
}

String _formatSpeed(double? metersPerSecond) {
  if (metersPerSecond == null || metersPerSecond <= 0) return '0 km/h';
  return '${(metersPerSecond * 3.6).round()} km/h';
}

bool _bookingMatchesBranch({
  required Booking booking,
  required BranchInfo branch,
  required String branchId,
}) {
  final bookingBranchId = booking.branchId?.trim();
  if (bookingBranchId == null || bookingBranchId.isEmpty) return true;
  if (bookingBranchId == branchId) return true;

  final bookingTerms = <String>[
    bookingBranchId,
    booking.branchName ?? '',
  ].map(_branchKey).where((item) => item.isNotEmpty).toSet();
  final branchTerms = <String>[
    branch.id,
    branch.name,
    branch.city,
    ...branch.aliases,
  ].map(_branchKey).where((item) => item.isNotEmpty).toSet();

  for (final bookingTerm in bookingTerms) {
    if (branchTerms.contains(bookingTerm)) return true;
    for (final branchTerm in branchTerms) {
      if (bookingTerm.contains(branchTerm) ||
          branchTerm.contains(bookingTerm)) {
        return true;
      }
    }
  }
  return false;
}

bool _userMatchesBranch({
  required AppUser user,
  required BranchInfo branch,
  required String branchId,
}) {
  final userBranchId = user.branchId?.trim();
  if (userBranchId != null && userBranchId.isNotEmpty) {
    if (userBranchId == branchId) return true;
  }
  final userTerms = <String>[
    user.branchId ?? '',
    user.branchName ?? '',
  ].map(_branchKey).where((item) => item.isNotEmpty).toSet();
  if (userTerms.isEmpty) {
    return user.role == UserRole.technician &&
        user.accountStatus == AccountStatus.approved;
  }
  final branchTerms = <String>[
    branch.id,
    branch.name,
    branch.city,
    ...branch.aliases,
  ].map(_branchKey).where((item) => item.isNotEmpty).toSet();
  for (final userTerm in userTerms) {
    if (branchTerms.contains(userTerm)) return true;
    for (final branchTerm in branchTerms) {
      if (userTerm.contains(branchTerm) || branchTerm.contains(userTerm)) {
        return true;
      }
    }
  }
  return false;
}

String _branchKey(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
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
