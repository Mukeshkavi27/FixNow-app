import 'package:cloud_firestore/cloud_firestore.dart';

class TechnicianLocation {
  const TechnicianLocation({
    required this.technicianId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.activeBookingId,
  });

  final String technicianId;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final String? activeBookingId;

  factory TechnicianLocation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return TechnicianLocation(
      technicianId: data['technicianId'] as String? ?? doc.id,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      activeBookingId: data['activeBookingId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'technicianId': technicianId,
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': Timestamp.fromDate(updatedAt),
        'activeBookingId': activeBookingId,
      };
}
