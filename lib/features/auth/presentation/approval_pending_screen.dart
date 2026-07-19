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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                      color: isRejected
                          ? const Color(0xFFD95C2A)
                          : AppTheme.primary,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: (isRejected
                                ? const Color(0xFFD95C2A)
                                : const Color(0xFFF38A1F))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isRejected ? 'Rejected' : 'Pending',
                        style: TextStyle(
                          color: isRejected
                              ? const Color(0xFFD95C2A)
                              : const Color(0xFFF38A1F),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isRejected
                          ? 'Your branch admin reviewed this technician request and did not approve access.'
                          : 'Your branch admin will review your technician account, verify the requested branch, and activate access shortly.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (isRejected &&
                        (user?.rejectionReason ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4EF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFF0C4B4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reason for rejection',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              user!.rejectionReason!,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                      onPressed: () =>
                          ref.read(authRepositoryProvider).signOut(),
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
