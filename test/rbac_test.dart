import 'package:fixnow/core/auth/app_permission.dart';
import 'package:fixnow/core/auth/route_access.dart';
import 'package:fixnow/core/enums/account_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('role parsing', () {
    test('legacy Admin maps to least-privileged Branch Admin', () {
      expect(UserRole.fromString('admin'), UserRole.branchAdmin);
      expect(UserRole.fromString('Branch Admin'), UserRole.branchAdmin);
      expect(UserRole.fromString('Super Admin'), UserRole.superAdmin);
    });

    test('unknown role never receives administrative access', () {
      final role = UserRole.fromString('owner');
      expect(role, UserRole.customer);
      expect(
          RolePermissions.allows(role, AppPermission.viewAllBranches), false);
    });
  });

  group('permission hierarchy', () {
    test('Super Admin contains global and branch permissions', () {
      expect(
        RolePermissions.allows(
          UserRole.superAdmin,
          AppPermission.manageGlobalOperations,
        ),
        true,
      );
      expect(
        RolePermissions.allows(
          UserRole.superAdmin,
          AppPermission.manageBranchOperations,
        ),
        true,
      );
    });

    test('Branch Admin cannot perform global operations', () {
      expect(
        RolePermissions.allows(
          UserRole.branchAdmin,
          AppPermission.manageBranchOperations,
        ),
        true,
      );
      expect(
        RolePermissions.allows(
          UserRole.branchAdmin,
          AppPermission.manageGlobalOperations,
        ),
        false,
      );
      expect(
        RolePermissions.allows(
          UserRole.branchAdmin,
          AppPermission.viewAllBranches,
        ),
        false,
      );
      expect(
        requiredPermissionForLocation('/super-admin'),
        AppPermission.manageGlobalOperations,
      );
    });
  });

  test('every role dashboard has an explicit route permission', () {
    expect(
      requiredPermissionForLocation('/customer'),
      AppPermission.useCustomerPortal,
    );
    expect(
      requiredPermissionForLocation('/technician'),
      AppPermission.useTechnicianPortal,
    );
    expect(
      requiredPermissionForLocation('/admin'),
      AppPermission.viewBranchDashboard,
    );
    expect(
      requiredPermissionForLocation('/super-admin'),
      AppPermission.manageGlobalOperations,
    );
  });

  group('account access validation', () {
    AppUser user({
      UserRole role = UserRole.customer,
      AccountStatus status = AccountStatus.approved,
      bool active = true,
      String? branchId,
    }) {
      return AppUser(
        uid: 'uid',
        name: 'User',
        email: 'user@example.com',
        phone: '9999999999',
        role: role,
        accountStatus: status,
        createdAt: DateTime(2026),
        isActive: active,
        branchId: branchId,
      );
    }

    test('inactive and rejected accounts are denied after authentication', () {
      expect(user(active: false).accessDenialReason, contains('inactive'));
      expect(
        user(status: AccountStatus.rejected).accessDenialReason,
        contains('rejected'),
      );
    });

    test('Branch Admin requires an explicit branch assignment', () {
      expect(
        user(role: UserRole.branchAdmin).accessDenialReason,
        contains('not assigned'),
      );
      expect(
        user(role: UserRole.branchAdmin, branchId: 'branch-a')
            .accessDenialReason,
        isNull,
      );
    });
  });
}
