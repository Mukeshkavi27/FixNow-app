enum AccountStatus {
  approved('Approved'),
  pendingApproval('Pending approval'),
  rejected('Rejected');

  const AccountStatus(this.label);
  final String label;

  static AccountStatus fromString(String? value) {
    final normalized = (value ?? AccountStatus.approved.name)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return switch (normalized) {
      'pendingapproval' || 'pending' => AccountStatus.pendingApproval,
      'rejected' => AccountStatus.rejected,
      _ => AccountStatus.approved,
    };
  }
}
