class BranchInfo {
  const BranchInfo({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.aliases = const [],
    this.radiusMeters = 35000,
  });

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final double radiusMeters;
  bool get hasCoordinates => latitude != 0 && longitude != 0;

  factory BranchInfo.fromJson(String id, Map<String, dynamic> data) {
    return BranchInfo(
      id: data['id'] as String? ?? id,
      name: data['name'] as String? ?? '',
      city: data['city'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      aliases: (data['aliases'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? 35000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'aliases': aliases,
        'radiusMeters': radiusMeters,
      };
}
