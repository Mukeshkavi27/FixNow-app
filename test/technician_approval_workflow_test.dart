import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/admin/data/admin_repository.dart';
import 'package:fixnow/features/auth/data/auth_repository.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:fixnow/features/auth/presentation/approval_pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only active approved technicians pass account access validation', () {
    AppUser technician(AccountStatus status, bool isActive) => AppUser(
          uid: 'tech',
          name: 'Technician',
          email: 'tech@fixnow.test',
          phone: '9999999999',
          role: UserRole.technician,
          accountStatus: status,
          createdAt: DateTime(2026, 7, 13),
          isActive: isActive,
          branchId: 'branch-chennai',
        );

    expect(technician(AccountStatus.approved, true).accessDenialReason, isNull);
    expect(
      technician(AccountStatus.pendingApproval, false).accessDenialReason,
      contains('waiting for approval'),
    );
    expect(
      technician(AccountStatus.rejected, false).accessDenialReason,
      contains('rejected'),
    );
  });

  test('rejection reason is required and normalized', () {
    expect(
      () => normalizeTechnicianRejectionReason('no'),
      throwsArgumentError,
    );
    expect(
      normalizeTechnicianRejectionReason('  Documents are unclear.  '),
      'Documents are unclear.',
    );
  });

  test('inactive technicians lose access and assignment eligibility', () {
    final active = AppUser(
      uid: 'tech-active',
      name: 'Active Technician',
      email: 'active@fixnow.test',
      phone: '9999999994',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      createdAt: DateTime(2026, 7, 13),
      isActive: true,
      branchId: 'branch-chennai',
    );
    final inactive = AppUser(
      uid: 'tech-inactive',
      name: 'Inactive Technician',
      email: 'inactive@fixnow.test',
      phone: '9999999993',
      role: UserRole.technician,
      accountStatus: AccountStatus.approved,
      createdAt: DateTime(2026, 7, 13),
      isActive: false,
      branchId: 'branch-chennai',
      inactivationReason: 'Technician left the branch.',
      inactivatedAt: DateTime(2026, 7, 13, 10),
      inactivatedBy: 'branch-admin-1',
    );

    expect(isTechnicianAssignable(active), isTrue);
    expect(isTechnicianAssignable(inactive), isFalse);
    expect(inactive.accessDenialReason, contains('inactive'));
  });

  test('inactivation reason is mandatory and normalized', () {
    expect(
      () => normalizeTechnicianInactivationReason('no'),
      throwsArgumentError,
    );
    expect(
      normalizeTechnicianInactivationReason('  Technician resigned.  '),
      'Technician resigned.',
    );
  });

  testWidgets('rejected technician sees status and rejection reason', (
    tester,
  ) async {
    final technician = AppUser(
      uid: 'tech-rejected',
      name: 'Rejected Technician',
      email: 'rejected@fixnow.test',
      phone: '9999999995',
      role: UserRole.technician,
      accountStatus: AccountStatus.rejected,
      createdAt: DateTime(2026, 7, 13),
      isActive: false,
      branchId: 'branch-chennai',
      branchName: 'FixNow Chennai',
      rejectionReason: 'Identity documents could not be verified.',
      rejectedAt: DateTime(2026, 7, 13, 12),
      rejectedBy: 'branch-admin-1',
    );

    expect(technician.accessDenialReason, contains('Identity documents'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(technician)),
        ],
        child: const MaterialApp(home: ApprovalPendingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Reason for rejection'), findsOneWidget);
    expect(
      find.text('Identity documents could not be verified.'),
      findsOneWidget,
    );
  });
}
