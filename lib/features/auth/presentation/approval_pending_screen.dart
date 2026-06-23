import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/account_status.dart';
import '../data/auth_repository.dart';

class ApprovalPendingScreen extends ConsumerWidget {
  const ApprovalPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final status = user?.accountStatus ?? AccountStatus.pendingApproval;
    final isRejected = status == AccountStatus.rejected;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                    Icon(
                      isRejected
                          ? Icons.cancel_outlined
                          : Icons.hourglass_top_rounded,
                      size: 56,
                      color:
                          isRejected ? const Color(0xFFD95C2A) : AppTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isRejected
                          ? 'Technician request rejected'
                          : 'Technician approval pending',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isRejected
                          ? 'Your branch admin has not approved this technician account. Please contact FixNow admin support to review the request.'
                          : 'Your branch admin will review your technician account, verify the requested branch, and activate access shortly.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (user?.branchName != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Requested branch: ${user!.branchName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => ref.read(authRepositoryProvider).signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
