import '../enums/user_role.dart';

enum AppPermission {
  useCustomerPortal,
  useTechnicianPortal,
  viewBranchDashboard,
  viewAllBranches,
  manageBranchOperations,
  manageGlobalOperations,
  monitorTechnicians,
}

class RolePermissions {
  const RolePermissions._();

  static const Map<UserRole, Set<AppPermission>> _matrix = {
    UserRole.customer: {
      AppPermission.useCustomerPortal,
    },
    UserRole.technician: {
      AppPermission.useTechnicianPortal,
    },
    UserRole.branchAdmin: {
      AppPermission.viewBranchDashboard,
      AppPermission.manageBranchOperations,
      AppPermission.monitorTechnicians,
    },
    UserRole.superAdmin: {
      AppPermission.viewBranchDashboard,
      AppPermission.viewAllBranches,
      AppPermission.manageBranchOperations,
      AppPermission.manageGlobalOperations,
      AppPermission.monitorTechnicians,
    },
  };

  static bool allows(UserRole role, AppPermission permission) =>
      _matrix[role]?.contains(permission) ?? false;

  static Set<AppPermission> forRole(UserRole role) =>
      Set.unmodifiable(_matrix[role] ?? const <AppPermission>{});
}
