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

  Map<String, dynamic> toJson() => {
        'technicianId': technicianId,
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': Timestamp.fromDate(updatedAt),
        'activeBookingId': activeBookingId,
      };
}
