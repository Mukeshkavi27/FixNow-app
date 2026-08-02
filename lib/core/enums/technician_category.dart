enum TechnicianCategory {
  junior('Junior'),
  intermediate('Intermediate'),
  senior('Senior');

  const TechnicianCategory(this.label);

  final String label;

  static TechnicianCategory fromString(String? value) {
    return TechnicianCategory.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TechnicianCategory.junior,
    );
  }
}
