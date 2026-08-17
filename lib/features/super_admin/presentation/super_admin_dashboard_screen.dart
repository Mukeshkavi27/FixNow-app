import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/fixnow_admin_shell.dart';
import '../../../app/widgets/resilient_asset_image.dart';
import '../../../core/branches/branch_info.dart';
import '../../../core/branches/branch_repository.dart';
import '../../../core/enums/booking_status.dart';
import '../../../core/services/reverse_geocoding_service.dart';
import '../../admin/data/admin_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/data/bill_repository.dart';
import '../../shared/data/review_repository.dart';
import '../../shared/data/technician_incentive_repository.dart';
import '../../shared/domain/bill.dart';
import '../../shared/domain/review.dart';
import '../../shared/domain/technician_incentive.dart';
import '../../shared/presentation/revenue_dashboard.dart';
import '../../shared/presentation/technician_performance_dashboard.dart';
import '../../technician/data/technician_repository.dart';
import '../../technician/domain/overtime_record.dart';
import '../../technician/presentation/overtime_summary_panel.dart';
import '../data/super_admin_api.dart';
import '../data/super_admin_repository.dart';
import '../domain/audit_log_entry.dart';

String _formatMoney(double amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

final superAdminBranchesProvider =
    StreamProvider.autoDispose<List<BranchInfo>>((ref) {
  return ref
      .watch(branchRepositoryProvider)
      .watchBranches(fallbackWhenEmpty: false);
});

final superAdminBookingsProvider =
    StreamProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingRepositoryProvider).watchAllBookings();
});

final superAdminTechniciansProvider =
    StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchTechnicians();
});

final superAdminCustomersProvider =
    StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(adminRepositoryProvider).watchCustomers();
});

final superAdminBranchAdminsProvider =
    StreamProvider.autoDispose<List<AppUser>>((ref) {
  return ref.watch(superAdminRepositoryProvider).watchBranchAdmins();
});

final superAdminBillsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  return ref.watch(billRepositoryProvider).watchAllBills();
});

final superAdminReviewsProvider =
    StreamProvider.autoDispose<List<Review>>((ref) {
  return ref.watch(reviewRepositoryProvider).watchAllReviews();
});

final superAdminIncentivesProvider =
    StreamProvider.autoDispose<List<TechnicianIncentive>>((ref) {
  return ref.watch(technicianIncentiveRepositoryProvider).watchAll();
});

final superAdminAuditProvider =
    StreamProvider.autoDispose<List<AuditLogEntry>>((ref) {
  return ref.watch(superAdminRepositoryProvider).watchAuditLogs();
});

final superAdminOvertimeProvider =
    StreamProvider.autoDispose<List<OvertimeRecord>>((ref) {
  return ref.watch(technicianRepositoryProvider).watchOvertime();
});

enum SuperAdminSection {
  overview('Overview', Icons.space_dashboard_outlined),
  branches('Branches', Icons.account_tree_outlined),
  bookings('Bookings', Icons.assignment_outlined),
  people('People', Icons.groups_outlined),
  performance('Performance', Icons.leaderboard_outlined),
  revenue('Revenue', Icons.currency_rupee),
  audit('Audit logs', Icons.policy_outlined);

  const SuperAdminSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final branches = ref.watch(superAdminBranchesProvider);
    final bookings = ref.watch(superAdminBookingsProvider);
    final technicians = ref.watch(superAdminTechniciansProvider);
    final customers = ref.watch(superAdminCustomersProvider);
    final branchAdmins = ref.watch(superAdminBranchAdminsProvider);
    final bills = ref.watch(superAdminBillsProvider);
    final reviews = ref.watch(superAdminReviewsProvider);
    final incentives = ref.watch(superAdminIncentivesProvider);
    final audit = ref.watch(superAdminAuditProvider);
    final overtime = ref.watch(superAdminOvertimeProvider);
    final errors = [
      branches,
      bookings,
      technicians,
      customers,
      branchAdmins,
      bills,
      reviews,
      incentives,
      audit,
      overtime,
    ].where((value) => value.hasError).toList();

    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SuperAdminDashboardView(
      currentUser: currentUser,
      branches: branches.valueOrNull ?? const [],
      bookings: bookings.valueOrNull ?? const [],
      technicians: technicians.valueOrNull ?? const [],
      customers: customers.valueOrNull ?? const [],
      branchAdmins: branchAdmins.valueOrNull ?? const [],
      bills: bills.valueOrNull ?? const [],
      reviews: reviews.valueOrNull ?? const [],
      incentives: incentives.valueOrNull ?? const [],
      auditLogs: audit.valueOrNull ?? const [],
      overtimeRecords: overtime.valueOrNull ?? const [],
      isLoading: branches.isLoading ||
          bookings.isLoading ||
          technicians.isLoading ||
          customers.isLoading ||
          branchAdmins.isLoading ||
          bills.isLoading ||
          reviews.isLoading ||
          incentives.isLoading ||
          audit.isLoading ||
          overtime.isLoading,
      errorMessage: errors.isEmpty ? null : errors.first.error.toString(),
      onCreateBranch: () => _showBranchDialog(context, ref, currentUser),
      onEditBranch: (branch) =>
          _showBranchDialog(context, ref, currentUser, branch: branch),
      onToggleBranch: (branch, active) =>
          _toggleBranch(context, ref, currentUser, branch, active),
      onCreateBranchAdmin: () => _showBranchAdminDialog(
        context,
        ref,
        branches.valueOrNull ?? const [],
      ),
      onToggleBranchAdmin: (admin, active) =>
          _toggleBranchAdmin(context, ref, admin, active),
      onResetBranchAdmin: (admin) =>
          _resetBranchAdminPassword(context, ref, admin),
      onTransferBranchAdmin: (admin) => _showBranchAdminTransferDialog(
        context,
        ref,
        admin,
        branches.valueOrNull ?? const [],
      ),
      onTransferTechnician: (technician) => _showTechnicianTransferDialog(
        context,
        ref,
        technician,
        branches.valueOrNull ?? const [],
      ),
      onRepairFinancialLinks: () =>
          _repairFinancialLinks(context, ref, currentUser),
      onSignOut: () => ref.read(authRepositoryProvider).signOut(),
    );
  }

  Future<void> _showBranchDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser actor, {
    BranchInfo? branch,
  }) async {
    final name = TextEditingController(text: branch?.name);
    final city = TextEditingController(text: branch?.city);
    final officeLocation = TextEditingController();
    double? latitude = branch?.hasCoordinates == true ? branch!.latitude : null;
    double? longitude = branch?.hasCoordinates == true ? branch!.longitude : null;
    final radius =
        TextEditingController(text: branch?.radiusMeters.toStringAsFixed(0));
    final aliases = TextEditingController(text: branch?.aliases.join(', '));
    final formKey = GlobalKey<FormState>();
    var saving = false;
    var locating = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(branch == null ? 'Create branch' : 'Edit branch'),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: officeLocation,
                      decoration: const InputDecoration(
                        labelText: 'Office location',
                        hintText: 'Enter the branch office address',
                      ),
                      validator: (value) {
                        if (latitude != null && longitude != null) return null;
                        if ((value ?? '').trim().isEmpty) {
                          return 'Enter the office address or use your current location.';
                        }
                        return 'Tap Find location to confirm this address.';
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: locating
                              ? null
                              : () async {
                                  setState(() => locating = true);
                                  try {
                                    final result = await ref
                                        .read(addressGeocodingServiceProvider)
                                        .search(officeLocation.text.trim());
                                    if (result == null) {
                                      throw StateError('Location could not be found. Add a more complete address.');
                                    }
                                    latitude = result.latitude;
                                    longitude = result.longitude;
                                    officeLocation.text = result.displayAddress;
                                  } catch (error) {
                                    if (dialogContext.mounted) {
                                      _showError(dialogContext, error);
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setState(() => locating = false);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.search_outlined),
                          label: const Text('Find location'),
                        ),
                        OutlinedButton.icon(
                          onPressed: locating
                              ? null
                              : () async {
                                  setState(() => locating = true);
                                  try {
                                    var permission = await Geolocator.checkPermission();
                                    if (permission == LocationPermission.denied) {
                                      permission = await Geolocator.requestPermission();
                                    }
                                    if (permission == LocationPermission.denied ||
                                        permission == LocationPermission.deniedForever) {
                                      throw StateError('Location permission is required to use the current office location.');
                                    }
                                    final position = await Geolocator.getCurrentPosition();
                                    latitude = position.latitude;
                                    longitude = position.longitude;
                                    final address = await ref
                                        .read(reverseGeocodingServiceProvider)
                                        .reverse(
                                          latitude: position.latitude,
                                          longitude: position.longitude,
                                        );
                                    officeLocation.text =
                                        address?.address ?? 'Current office location';
                                  } catch (error) {
                                    if (dialogContext.mounted) {
                                      _showError(dialogContext, error);
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setState(() => locating = false);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.my_location_outlined),
                          label: const Text('Use current location'),
                        ),
                      ],
                    ),
                    if (latitude != null && longitude != null) ...[
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '✓ Office location confirmed',
                          style: TextStyle(
                            color: AppTheme.instantGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: radius,
                      decoration: const InputDecoration(
                        labelText: 'Service radius (metres)',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _number,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: aliases,
                      decoration: const InputDecoration(
                        labelText: 'Service areas (comma-separated)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => saving = true);
                      final value = BranchInfo(
                        id: branch?.id ?? '',
                        name: name.text.trim(),
                        city: city.text.trim(),
                        latitude: latitude!,
                        longitude: longitude!,
                        radiusMeters: double.parse(radius.text),
                        aliases: aliases.text
                            .split(',')
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList(),
                        isActive: branch?.isActive ?? true,
                      );
                      try {
                        final repository =
                            ref.read(superAdminRepositoryProvider);
                        if (branch == null) {
                          await repository.createBranch(
                            branch: value,
                            actorId: actor.uid,
                          );
                        } else {
                          await repository.updateBranch(
                            branch: value,
                            actorId: actor.uid,
                          );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        setState(() => saving = false);
                        if (dialogContext.mounted) {
                          _showError(dialogContext, error);
                        }
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save branch'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    city.dispose();
    officeLocation.dispose();
    radius.dispose();
    aliases.dispose();
  }

  Future<void> _repairFinancialLinks(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
  ) async {
    try {
      final result = await ref
          .read(superAdminRepositoryProvider)
          .backfillFinancialBranches(actorId: actor.uid);
      ref.invalidate(superAdminBillsProvider);
      ref.invalidate(superAdminTechniciansProvider);
      ref.invalidate(superAdminIncentivesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.totalUpdated == 0
                ? 'Financial branch links are already up to date.'
                : 'Updated ${result.billsUpdated} bills, '
                    '${result.techniciansUpdated} technicians and '
                    '${result.incentivesUpdated} incentives.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showBranchAdminDialog(
    BuildContext context,
    WidgetRef ref,
    List<BranchInfo> branches,
  ) async {
    final activeBranches = branches.where((branch) => branch.isActive).toList();
    if (activeBranches.isEmpty) {
      _showError(context, 'Create an active branch first.');
      return;
    }
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var branchId = activeBranches.first.id;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create Branch Admin'),
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
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Temporary password',
                        helperText: 'Minimum 6 characters',
                      ),
                      validator: (value) => (value?.length ?? 0) < 6
                          ? 'Use at least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: branchId,
                      decoration:
                          const InputDecoration(labelText: 'Assigned branch'),
                      items: activeBranches
                          .map(
                            (branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => branchId = value ?? branchId,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => saving = true);
                      try {
                        await ref.read(superAdminApiProvider).createBranchAdmin(
                              name: name.text,
                              email: email.text,
                              phone: phone.text,
                              password: password.text,
                              branchId: branchId,
                            );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        setState(() => saving = false);
                        if (dialogContext.mounted) {
                          _showError(dialogContext, error);
                        }
                      }
                    },
              child: Text(saving ? 'Creating...' : 'Create admin'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
  }

  Future<void> _toggleBranch(
    BuildContext context,
    WidgetRef ref,
    AppUser actor,
    BranchInfo branch,
    bool active,
  ) async {
    try {
      await ref.read(superAdminRepositoryProvider).setBranchActive(
            branch: branch,
            isActive: active,
            actorId: actor.uid,
          );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _toggleBranchAdmin(
    BuildContext context,
    WidgetRef ref,
    AppUser admin,
    bool active,
  ) async {
    try {
      await ref.read(superAdminApiProvider).setBranchAdminActive(
            uid: admin.uid,
            isActive: active,
          );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showBranchAdminTransferDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser admin,
    List<BranchInfo> branches,
  ) async {
    final destinations = branches
        .where((branch) => branch.isActive && branch.id != admin.branchId)
        .toList();
    if (destinations.isEmpty) {
      _showError(context, 'Create or activate another branch first.');
      return;
    }
    var branchId = destinations.first.id;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Transfer Branch Admin'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${admin.name} is currently assigned to ${admin.branchName ?? 'an unassigned branch'}.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: branchId,
                  decoration: const InputDecoration(
                    labelText: 'Transfer to branch',
                  ),
                  items: destinations
                      .map(
                        (branch) => DropdownMenuItem(
                          value: branch.id,
                          child: Text('${branch.name} - ${branch.city}'),
                        ),
                      )
                      .toList(),
                  onChanged:
                      saving ? null : (value) => branchId = value ?? branchId,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Access to the previous branch is removed immediately after transfer.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(superAdminApiProvider)
                            .transferBranchAdmin(
                              uid: admin.uid,
                              branchId: branchId,
                            );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Branch Admin transferred.'),
                            ),
                          );
                        }
                      } catch (error) {
                        setState(() => saving = false);
                        if (dialogContext.mounted) {
                          _showError(dialogContext, error);
                        }
                      }
                    },
              icon: const Icon(Icons.swap_horiz),
              label: Text(saving ? 'Transferring...' : 'Transfer admin'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetBranchAdminPassword(
    BuildContext context,
    WidgetRef ref,
    AppUser admin,
  ) async {
    try {
      final link = await ref
          .read(superAdminApiProvider)
          .createPasswordResetLink(admin.uid);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            link.isEmpty ? 'Password reset email sent' : 'Password reset link',
          ),
          content: SizedBox(
            width: 520,
            child: link.isEmpty
                ? Text('A secure reset link was emailed to ${admin.email}.')
                : SelectableText(link),
          ),
          actions: [
            if (link.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy link'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showTechnicianTransferDialog(
    BuildContext context,
    WidgetRef ref,
    AppUser technician,
    List<BranchInfo> branches,
  ) async {
    final destinations = branches
        .where(
          (branch) => branch.isActive && branch.id != technician.branchId,
        )
        .toList();
    if (destinations.isEmpty) {
      _showError(context, 'Create or activate another branch first.');
      return;
    }
    var branchId = destinations.first.id;
    var saving = false;
    var futureRevenueStaysWithPreviousBranch = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Change technician branch'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${technician.name} currently works from '
                  '${technician.branchName ?? 'an unassigned branch'}.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: branchId,
                  decoration: const InputDecoration(
                    labelText: 'New operating branch',
                  ),
                  items: [
                    for (final branch in destinations)
                      DropdownMenuItem(
                        value: branch.id,
                        child: Text('${branch.name} - ${branch.city}'),
                      ),
                  ],
                  onChanged:
                      saving ? null : (value) => branchId = value ?? branchId,
                ),
                const SizedBox(height: 14),
                Text(
                  'Revenue ownership for future bills',
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                RadioListTile<bool>(
                  value: false,
                  groupValue: futureRevenueStaysWithPreviousBranch,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Credit future bills to the new branch'),
                  subtitle: const Text(
                    'Recommended. Past bills and collections stay with the old branch.',
                  ),
                  onChanged: saving
                      ? null
                      : (value) => setState(() =>
                          futureRevenueStaysWithPreviousBranch = value ?? false),
                ),
                RadioListTile<bool>(
                  value: true,
                  groupValue: futureRevenueStaysWithPreviousBranch,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep future bills with the old branch'),
                  subtitle: const Text(
                    'Use for a temporary operating transfer.',
                  ),
                  onChanged: saving
                      ? null
                      : (value) => setState(() =>
                          futureRevenueStaysWithPreviousBranch = value ?? false),
                ),
                const Text(
                  'A technician with an active job cannot be transferred. Already generated bills are never moved.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(superAdminApiProvider)
                            .transferTechnician(
                              uid: technician.uid,
                              branchId: branchId,
                              futureRevenueStaysWithPreviousBranch:
                                  futureRevenueStaysWithPreviousBranch,
                            );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Technician branch changed.'),
                            ),
                          );
                        }
                      } catch (error) {
                        setState(() => saving = false);
                        if (dialogContext.mounted) {
                          _showError(dialogContext, error);
                        }
                      }
                    },
              icon: const Icon(Icons.swap_horiz),
              label: Text(saving ? 'Changing...' : 'Change branch'),
            ),
          ],
        ),
      ),
    );
  }

  static String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  static String? _number(String? value) =>
      double.tryParse(value ?? '') == null ? 'Enter a valid number' : null;

  static void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }
}

class SuperAdminDashboardView extends StatefulWidget {
  const SuperAdminDashboardView({
    super.key,
    required this.currentUser,
    required this.branches,
    required this.bookings,
    required this.technicians,
    required this.customers,
    required this.branchAdmins,
    required this.bills,
    required this.reviews,
    this.incentives = const [],
    required this.auditLogs,
    this.overtimeRecords = const [],
    this.isLoading = false,
    this.errorMessage,
    this.onCreateBranch,
    this.onEditBranch,
    this.onToggleBranch,
    this.onCreateBranchAdmin,
    this.onToggleBranchAdmin,
    this.onResetBranchAdmin,
    this.onTransferBranchAdmin,
    this.onTransferTechnician,
    this.onRepairFinancialLinks,
    this.onSignOut,
    this.initialSection = SuperAdminSection.overview,
  });

  final AppUser currentUser;
  final List<BranchInfo> branches;
  final List<Booking> bookings;
  final List<AppUser> technicians;
  final List<AppUser> customers;
  final List<AppUser> branchAdmins;
  final List<Bill> bills;
  final List<Review> reviews;
  final List<TechnicianIncentive> incentives;
  final List<AuditLogEntry> auditLogs;
  final List<OvertimeRecord> overtimeRecords;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onCreateBranch;
  final ValueChanged<BranchInfo>? onEditBranch;
  final void Function(BranchInfo branch, bool active)? onToggleBranch;
  final VoidCallback? onCreateBranchAdmin;
  final void Function(AppUser admin, bool active)? onToggleBranchAdmin;
  final ValueChanged<AppUser>? onResetBranchAdmin;
  final ValueChanged<AppUser>? onTransferBranchAdmin;
  final ValueChanged<AppUser>? onTransferTechnician;
  final VoidCallback? onRepairFinancialLinks;
  final VoidCallback? onSignOut;
  final SuperAdminSection initialSection;

  @override
  State<SuperAdminDashboardView> createState() =>
      _SuperAdminDashboardViewState();
}

class _SuperAdminDashboardViewState extends State<SuperAdminDashboardView> {
  late SuperAdminSection _section = widget.initialSection;
  String _bookingBranchFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return FixNowAdminShell(
      destinations: [
        for (final section in SuperAdminSection.values)
          FixNowAdminDestination(
            id: section.name,
            label: section.label,
            icon: section.icon,
          ),
      ],
      selectedId: _section.name,
      onDestinationSelected: (id) {
        setState(() {
          _section = SuperAdminSection.values.firstWhere(
            (section) => section.name == id,
          );
        });
      },
      userName: widget.currentUser.name,
      roleLabel: 'Super Admin',
      consoleLabel: 'Super Admin Console',
      contextLabel: 'All FixNow branches',
      onSignOut: widget.onSignOut,
      isLoading: widget.isLoading,
      errorMessage: widget.errorMessage,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.isLoading &&
              widget.branches.isEmpty &&
              widget.bookings.isEmpty &&
              widget.technicians.isEmpty) {
            return const FixNowAdminSkeleton(
              label: 'Loading Super Admin dashboard',
            );
          }
          return SingleChildScrollView(
            padding: EdgeInsets.all(constraints.maxWidth >= 700 ? 28 : 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: _content(),
              ),
            ),
          );
        },
      ),
    );
  }

  // Kept as a compatibility fallback while existing deep-link tests migrate to
  // the shared shell navigation.
  // ignore: unused_element
  Widget _navigation({bool closeDrawer = false}) {
    return ColoredBox(
      color: const Color(0xFF0D2344),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
              child: Row(
                children: [
                  const ResilientAssetImage(
                    assetName: 'assets/images/fixnow_logo.png',
                    width: 42,
                    height: 42,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FixNow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Super Admin Console',
                          style: TextStyle(color: Color(0xFF9CB5D9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...SuperAdminSection.values.map(
              (item) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: ListTile(
                  selected: _section == item,
                  selectedTileColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(item.icon),
                  iconColor: const Color(0xFFB9CAE3),
                  selectedColor: Colors.white,
                  textColor: const Color(0xFFD7E2F2),
                  title: Text(item.label),
                  onTap: () {
                    setState(() => _section = item);
                    if (closeDrawer) Navigator.pop(context);
                  },
                ),
              ),
            ),
            const Spacer(),
            const Divider(color: Color(0xFF284260)),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.accent,
                child: Icon(Icons.shield_outlined, color: Colors.white),
              ),
              title: Text(
                widget.currentUser.name,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Super Admin',
                style: TextStyle(color: Color(0xFF9CB5D9)),
              ),
              trailing: IconButton(
                tooltip: 'Sign out',
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() => switch (_section) {
        SuperAdminSection.overview => _overview(),
        SuperAdminSection.branches => _branches(),
        SuperAdminSection.bookings => _bookings(),
        SuperAdminSection.people => _people(),
        SuperAdminSection.performance => _performance(),
        SuperAdminSection.revenue => _revenue(),
        SuperAdminSection.audit => _audit(),
      };

  String? _revenueBranchId(Bill bill) {
    AppUser? technician;
    for (final item in widget.technicians) {
      if (item.uid == bill.technicianId) {
        technician = item;
        break;
      }
    }
    return bill.revenueBranchId ??
        bill.branchId ??
        technician?.nativeBranchId ??
        technician?.branchId;
  }

  Widget _pageHeader(String title, String subtitle,
      {List<Widget> actions = const []}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: compact ? 23 : null,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (var index = 0; index < actions.length; index++) ...[
                  SizedBox(width: double.infinity, child: actions[index]),
                  if (index != actions.length - 1) const SizedBox(height: 8),
                ],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: actions,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _overview() {
    final paid = widget.bills.where((bill) => bill.isPaid).toList();
    final revenue = paid.fold<double>(0, (sum, bill) => sum + bill.amount);
    final activeJobs = widget.bookings
        .where((booking) => booking.status != BookingStatus.closed)
        .length;
    final completed = widget.bookings
        .where((booking) => booking.status == BookingStatus.closed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'System overview',
          'All branches and operations in one trusted view',
          actions: [
            FilledButton.icon(
              onPressed: widget.onCreateBranch,
              style: _compactFilledButtonStyle,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create branch'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onCreateBranchAdmin,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Create Branch Admin'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _metricGrid([
          _Metric('Total revenue', _formatMoney(revenue), Icons.currency_rupee,
              AppTheme.instantGreen),
          _Metric(
              'Active branches',
              '${widget.branches.where((b) => b.isActive).length}',
              Icons.account_tree,
              AppTheme.primary),
          _Metric('Active bookings', '$activeJobs', Icons.handyman_outlined,
              AppTheme.accent),
          _Metric('Completed jobs', '$completed', Icons.task_alt,
              const Color(0xFF7B61FF)),
          _Metric('Technicians', '${widget.technicians.length}',
              Icons.engineering_outlined, const Color(0xFF00A6A6)),
          _Metric('Customers', '${widget.customers.length}',
              Icons.people_outline, const Color(0xFFB35C00)),
        ]),
        if (widget.overtimeRecords.isNotEmpty) ...[
          const SizedBox(height: 24),
          OvertimeSummaryPanel(
            records: widget.overtimeRecords,
            bookings: widget.bookings,
            bills: widget.bills,
            technicians: widget.technicians,
            title: 'Network overtime',
          ),
        ],
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 850;
            final children = [
              Expanded(flex: 3, child: _branchPerformanceCard()),
              Expanded(flex: 2, child: _statusCard()),
            ];
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    children[0],
                    const SizedBox(width: 18),
                    children[1],
                  ])
                : Column(children: [
                    _branchPerformanceCard(),
                    const SizedBox(height: 18),
                    _statusCard(),
                  ]);
          },
        ),
      ],
    );
  }

  Widget _metricGrid(List<_Metric> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 1150
            ? 3
            : constraints.maxWidth > 620
                ? 2
                : constraints.maxWidth >= 340
                    ? 2
                    : 1;
        final width = (constraints.maxWidth - (count - 1) * 16) / count;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: metrics
              .map((metric) =>
                  SizedBox(width: width, child: _MetricCard(metric)))
              .toList(),
        );
      },
    );
  }

  Widget _branchPerformanceCard() {
    final rows = widget.branches.map((branch) {
      final bookings =
          widget.bookings.where((item) => item.branchId == branch.id).length;
      final revenue = widget.bills
          .where(
            (bill) => bill.isPaid && _revenueBranchId(bill) == branch.id,
          )
          .fold<double>(0, (sum, bill) => sum + bill.amount);
      return (branch, bookings, revenue);
    }).toList()
      ..sort((a, b) => b.$3.compareTo(a.$3));
    return _Panel(
      title: 'Branch performance',
      subtitle: 'Revenue and booking volume',
      child: Column(
        children: rows.isEmpty
            ? [const _EmptyMessage('No branches configured yet')]
            : rows.take(6).map((row) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: row.$1.isActive
                            ? const Color(0xFFE8F1FF)
                            : const Color(0xFFF1F3F5),
                        child: const Icon(Icons.business_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.$1.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text('${row.$2} bookings · ${row.$1.city}',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      Text(_formatMoney(row.$3),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _statusCard() {
    final statusCounts = <BookingStatus, int>{
      for (final status in BookingStatus.values)
        status: widget.bookings.where((b) => b.status == status).length,
    };
    final visible = statusCounts.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _Panel(
      title: 'Booking analytics',
      subtitle: '${widget.bookings.length} total bookings',
      child: Column(
        children: visible.isEmpty
            ? [const _EmptyMessage('No booking activity yet')]
            : visible.take(7).map((entry) {
                final ratio = widget.bookings.isEmpty
                    ? 0.0
                    : entry.value / widget.bookings.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(entry.key.label)),
                          Text('${entry.value}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _branches() {
    final bookingsByBranch = <String, List<Booking>>{};
    final bookingBranchById = <String, String>{};
    final customerIdsByBranch = <String, Set<String>>{};
    for (final booking in widget.bookings) {
      final branchId = booking.branchId;
      if (branchId == null || branchId.isEmpty) continue;
      bookingsByBranch.putIfAbsent(branchId, () => []).add(booking);
      bookingBranchById[booking.id] = branchId;
      customerIdsByBranch
          .putIfAbsent(branchId, () => <String>{})
          .add(booking.customerId);
    }
    final revenueByBranch = <String, double>{};
    for (final bill in widget.bills.where((item) => item.isPaid)) {
      final branchId =
          _revenueBranchId(bill) ?? bookingBranchById[bill.bookingId];
      if (branchId == null || branchId.isEmpty) continue;
      revenueByBranch.update(
        branchId,
        (value) => value + bill.amount,
        ifAbsent: () => bill.amount,
      );
    }
    final technicianCountByBranch = <String, int>{};
    for (final technician in widget.technicians) {
      final branchId = technician.branchId;
      if (branchId == null || branchId.isEmpty) continue;
      technicianCountByBranch.update(branchId, (value) => value + 1,
          ifAbsent: () => 1);
    }
    final adminCountByBranch = <String, int>{};
    for (final admin in widget.branchAdmins) {
      final branchId = admin.branchId;
      if (branchId == null || branchId.isEmpty) continue;
      adminCountByBranch.update(branchId, (value) => value + 1,
          ifAbsent: () => 1);
    }
    for (final customer in widget.customers) {
      final branchId = customer.branchId;
      if (branchId == null || branchId.isEmpty) continue;
      customerIdsByBranch
          .putIfAbsent(branchId, () => <String>{})
          .add(customer.uid);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'Branch management',
          'Create, edit, activate, and deactivate service branches',
          actions: [
            FilledButton.icon(
              onPressed: widget.onCreateBranch,
              style: _compactFilledButtonStyle,
              icon: const Icon(Icons.add),
              label: const Text('Create branch'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (widget.branches.isEmpty)
          const _Panel(
            title: 'Branches',
            child: _EmptyMessage('No branches configured'),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth > 1050
                  ? 3
                  : constraints.maxWidth > 650
                      ? 2
                      : 1;
              final width = (constraints.maxWidth - (count - 1) * 16) / count;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: widget.branches.map((branch) {
                  final branchBookings =
                      bookingsByBranch[branch.id] ?? const <Booking>[];
                  return SizedBox(
                    width: width,
                    child: _BranchCard(
                      branch: branch,
                      bookings: branchBookings.length,
                      revenue: revenueByBranch[branch.id] ?? 0,
                      technicians: technicianCountByBranch[branch.id] ?? 0,
                      customers: customerIdsByBranch[branch.id]?.length ?? 0,
                      completedJobs: branchBookings
                          .where(
                            (item) => item.status == BookingStatus.closed,
                          )
                          .length,
                      pendingJobs: branchBookings
                          .where(
                            (item) => item.status != BookingStatus.closed,
                          )
                          .length,
                      admins: adminCountByBranch[branch.id] ?? 0,
                      onEdit: widget.onEditBranch,
                      onToggle: widget.onToggleBranch,
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _bookings() {
    final filtered = _bookingBranchFilter == 'all'
        ? widget.bookings
        : widget.bookings
            .where((booking) => booking.branchId == _bookingBranchFilter)
            .toList();
    final items = [...filtered]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'All bookings',
          'Cross-branch service activity',
          actions: [
            Container(
              constraints: const BoxConstraints(minWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _bookingBranchFilter,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All branches'),
                    ),
                    for (final branch in widget.branches)
                      DropdownMenuItem(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _bookingBranchFilter = value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Panel(
          title: 'Bookings',
          subtitle: _bookingBranchFilter == 'all'
              ? '${items.length} records across all branches'
              : '${items.length} of ${widget.bookings.length} records',
          child: items.isEmpty
              ? const _EmptyMessage('No bookings found')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 700) {
                      return Column(
                        children: items
                            .take(30)
                            .map((booking) => _MobileBookingCard(booking))
                            .toList(),
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Customer')),
                          DataColumn(label: Text('Service')),
                          DataColumn(label: Text('Branch')),
                          DataColumn(label: Text('Technician')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Created')),
                        ],
                        rows: items.take(100).map((booking) {
                          return DataRow(cells: [
                            DataCell(Text(booking.customerName)),
                            DataCell(Text(booking.applianceType)),
                            DataCell(Text(booking.branchName ?? 'Unassigned')),
                            DataCell(
                                Text(booking.technicianName ?? 'Unassigned')),
                            DataCell(_StatusPill(booking.status.label)),
                            DataCell(Text(DateFormat('dd MMM yyyy')
                                .format(booking.createdAt))),
                          ]);
                        }).toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _people() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'People and access',
          'Manage Branch Admins and view platform users',
          actions: [
            FilledButton.icon(
              onPressed: widget.onCreateBranchAdmin,
              style: _compactFilledButtonStyle,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Branch Admin'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Panel(
          title: 'Branch Administrators',
          subtitle: '${widget.branchAdmins.length} accounts',
          child: widget.branchAdmins.isEmpty
              ? const _EmptyMessage('No Branch Admin accounts')
              : Column(
                  children: widget.branchAdmins.map((admin) {
                    return _PersonRow(
                      user: admin,
                      detail: admin.branchName ?? 'Branch not assigned',
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                widget.onTransferBranchAdmin?.call(admin),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('Transfer'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                widget.onResetBranchAdmin?.call(admin),
                            icon: const Icon(Icons.lock_reset_outlined),
                            label: const Text('Reset password'),
                          ),
                          Switch(
                            value: admin.isActive,
                            onChanged: (value) =>
                                widget.onToggleBranchAdmin?.call(admin, value),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 780;
            final tech = _Panel(
              title: 'Technicians',
              subtitle: '${widget.technicians.length} accounts',
              child: Column(
                children: widget.technicians
                    .take(12)
                    .map((user) => _PersonRow(
                          user: user,
                          detail:
                              'Current: ${user.branchName ?? 'No branch'} · '
                              'Revenue: ${user.nativeBranchName ?? user.branchName ?? 'No native branch'}',
                          trailing: TextButton.icon(
                            onPressed: () =>
                                widget.onTransferTechnician?.call(user),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('Change branch'),
                          ),
                        ))
                    .toList(),
              ),
            );
            final customers = _Panel(
              title: 'Customers',
              subtitle: '${widget.customers.length} accounts',
              child: Column(
                children: widget.customers
                    .take(12)
                    .map((user) => _PersonRow(
                          user: user,
                          detail: user.email,
                        ))
                    .toList(),
              ),
            );
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: tech),
                    const SizedBox(width: 18),
                    Expanded(child: customers),
                  ])
                : Column(
                    children: [tech, const SizedBox(height: 18), customers]);
          },
        ),
      ],
    );
  }

  Widget _revenue() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: widget.onRepairFinancialLinks,
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Repair legacy revenue links'),
          ),
        ),
        const SizedBox(height: 12),
        RevenueDashboard(
          bills: widget.bills,
          bookings: widget.bookings,
          branches: widget.branches,
          technicians: widget.technicians,
          incentives: widget.incentives,
          now: DateTime.now(),
          subtitle: 'Paid bill performance across the FixNow network',
        ),
      ],
    );
  }

  Widget _performance() {
    return TechnicianPerformanceDashboard(
      technicians: widget.technicians,
      bookings: widget.bookings,
      bills: widget.bills,
      reviews: widget.reviews,
      branches: widget.branches,
      title: 'Technician performance',
      subtitle: 'Network leaderboard, service quality, and branch ranking',
    );
  }

  Widget _audit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader('Audit logs', 'Immutable administrative activity history'),
        const SizedBox(height: 22),
        _Panel(
          title: 'Latest activity',
          subtitle: '${widget.auditLogs.length} entries',
          child: widget.auditLogs.isEmpty
              ? const _EmptyMessage('No administrative actions recorded')
              : Column(
                  children: widget.auditLogs.map((entry) {
                    final usersById = {
                      widget.currentUser.uid: widget.currentUser,
                      for (final user in [
                        ...widget.branchAdmins,
                        ...widget.technicians,
                        ...widget.customers,
                      ])
                        user.uid: user,
                    };
                    final actor = usersById[entry.actorId];
                    final actorName = (actor?.name.trim().isNotEmpty ?? false)
                        ? actor!.name.trim()
                        : _auditActorRoleLabel(entry.actorRole);
                    final branchName = entry.branchId == null
                        ? null
                        : widget.branches
                            .where((branch) => branch.id == entry.branchId)
                            .map((branch) => branch.name)
                            .cast<String?>()
                            .firstOrNull;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8F1FF),
                        child: Icon(Icons.verified_user_outlined),
                      ),
                      title: Text(entry.summary),
                      subtitle: Text(
                        'By $actorName · ${_auditActorRoleLabel(entry.actorRole)}\n'
                        '${entry.action} · ${DateFormat('dd MMM yyyy, hh:mm a').format(entry.createdAt)}',
                      ),
                      trailing: branchName == null
                          ? null
                          : Text(branchName,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  static final ButtonStyle _compactFilledButtonStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 46),
    padding: const EdgeInsets.symmetric(horizontal: 18),
  );
}

String _auditActorRoleLabel(String role) {
  return switch (role) {
    'superAdmin' => 'Super Admin',
    'branchAdmin' => 'Branch Admin',
    'technician' => 'Technician',
    'customer' => 'Customer',
    _ => 'FixNow Admin',
  };
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.metric);
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 220;
        final icon = Container(
          width: compact ? 42 : 48,
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(metric.icon, color: metric.color),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              metric.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 20 : 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        );
        return FixNowHoverCard(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(height: 12),
                    details,
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _MobileBookingCard extends StatelessWidget {
  const _MobileBookingCard(this.booking);

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(booking.status.label),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                booking.applianceType,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${booking.branchName ?? 'Unassigned'} • '
                '${booking.technicianName ?? 'Technician unassigned'}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('dd MMM yyyy').format(booking.createdAt),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.bookings,
    required this.revenue,
    required this.technicians,
    required this.customers,
    required this.completedJobs,
    required this.pendingJobs,
    required this.admins,
    this.onEdit,
    this.onToggle,
  });
  final BranchInfo branch;
  final int bookings;
  final double revenue;
  final int technicians;
  final int customers;
  final int completedJobs;
  final int pendingJobs;
  final int admins;
  final ValueChanged<BranchInfo>? onEdit;
  final void Function(BranchInfo, bool)? onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.business_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(branch.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(branch.city,
                          style:
                              const TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                _StatusPill(branch.isActive ? 'Active' : 'Inactive',
                    active: branch.isActive),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Branch dashboard',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BranchMetric(label: 'Bookings', value: '$bookings'),
                _BranchMetric(
                  label: 'Revenue',
                  value: _formatMoney(revenue),
                ),
                _BranchMetric(label: 'Technicians', value: '$technicians'),
                _BranchMetric(label: 'Customers', value: '$customers'),
                _BranchMetric(label: 'Completed', value: '$completedJobs'),
                _BranchMetric(label: 'Pending', value: '$pendingJobs'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$admins Branch Admin(s) · Radius ${(branch.radiusMeters / 1000).toStringAsFixed(0)} km',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onEdit?.call(branch),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: branch.isActive,
                  onChanged: (value) => onToggle?.call(branch, value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchMetric extends StatelessWidget {
  const _BranchMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user, required this.detail, this.trailing});
  final AppUser user;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final status = trailing ??
          _StatusPill(user.isActive ? 'Active' : 'Inactive',
              active: user.isActive);
      final identity = Row(
        children: [
          CircleAvatar(
            child: Text(user.name.trim().isEmpty
                ? '?'
                : user.name.trim()[0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 560 && trailing != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: status),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 8),
            status,
          ],
        ),
      );
    });
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, {this.active = true});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE7F8F0) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF087F5B) : AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(message,
            style: const TextStyle(color: AppTheme.textSecondary)),
      ),
    );
  }
}
