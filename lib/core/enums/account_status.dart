enum AccountStatus {
  approved('Approved'),
  pendingApproval('Pending approval'),
  rejected('Rejected');

  const AccountStatus(this.label);
  final String label;

  static AccountStatus fromString(String? value) {
    return AccountStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => AccountStatus.approved,
    );
  }
}
