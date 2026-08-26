import 'package:cloud_firestore/cloud_firestore.dart';

class TechnicianLocation {
  const TechnicianLocation({
    required this.technicianId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.activeBookingId,
    this.heading,
    this.speed,
    this.accuracy,
    this.bearing,
    this.isOnline = true,
    this.branchId,
    this.isOnDuty = false,
    this.shiftClosedAt,
    this.attendanceId,
    this.isMocked = false,
    this.capturedAt,
  });

  final String technicianId;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final String? activeBookingId;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final double? bearing;
  final bool isOnline;
  final String? branchId;
  final bool isOnDuty;
  final DateTime? shiftClosedAt;
  final String? attendanceId;
  final bool isMocked;
  final DateTime? capturedAt;

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
      heading: (data['heading'] as num?)?.toDouble(),
      speed: (data['speed'] as num?)?.toDouble(),
      accuracy: (data['accuracy'] as num?)?.toDouble(),
      bearing: (data['bearing'] as num?)?.toDouble(),
      isOnline: data['isOnline'] as bool? ?? true,
      branchId: data['branchId'] as String?,
      isOnDuty: data['isOnDuty'] as bool? ?? false,
      shiftClosedAt: (data['shiftClosedAt'] as Timestamp?)?.toDate(),
      attendanceId: data['attendanceId'] as String?,
      isMocked: data['isMocked'] as bool? ?? false,
      capturedAt: (data['capturedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'technicianId': technicianId,
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': Timestamp.fromDate(updatedAt),
        'activeBookingId': activeBookingId,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
        if (accuracy != null) 'accuracy': accuracy,
        if (bearing != null) 'bearing': bearing,
        'isOnline': isOnline,
        'isOnDuty': isOnDuty,
        if (attendanceId != null) 'attendanceId': attendanceId,
        if (branchId != null) 'branchId': branchId,
        'isMocked': isMocked,
        'capturedAt': Timestamp.fromDate(capturedAt ?? updatedAt),
      };
}
