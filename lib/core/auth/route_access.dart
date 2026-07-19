import 'app_permission.dart';

AppPermission? requiredPermissionForLocation(String location) {
  if (location == '/customer' || location.startsWith('/customer/')) {
    return AppPermission.useCustomerPortal;
  }
  if (location.startsWith('/book/')) {
    return AppPermission.useCustomerPortal;
  }
  if (location == '/technician') {
    return AppPermission.useTechnicianPortal;
  }
  if (location == '/admin' || location.startsWith('/admin/')) {
    return AppPermission.viewBranchDashboard;
  }
  if (location == '/super-admin' || location.startsWith('/super-admin/')) {
    return AppPermission.manageGlobalOperations;
  }
  return null;
}
