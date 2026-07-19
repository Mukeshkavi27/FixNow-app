enum UserRole {
  customer,
  technician,
  branchAdmin,
  superAdmin;

  bool get isAdmin =>
      this == UserRole.branchAdmin || this == UserRole.superAdmin;

  String get label => switch (this) {
        UserRole.customer => 'Customer',
        UserRole.technician => 'Technician',
        UserRole.branchAdmin => 'Branch Admin',
        UserRole.superAdmin => 'Super Admin',
      };

  static UserRole fromString(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return switch (normalized) {
      // `admin` is the legacy persisted value. It intentionally maps to the
      // least-privileged administrator role until the migration is applied.
      'admin' || 'branchadmin' => UserRole.branchAdmin,
      'superadmin' => UserRole.superAdmin,
      'technician' || 'tech' => UserRole.technician,
      _ => UserRole.customer,
    };
  }
}
