import 'package:cloud_firestore/cloud_firestore.dart';

class Attendance {
  const Attendance({
    required this.id,
    required this.technicianId,
    required this.selfieUrl,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'present',
    this.faceMatchPassed = false,
    this.geofencePassed = false,
    this.faceMatchScore,
    this.markedBy = 'technician',
    this.adminOverrideBy,
    this.adminOverrideReason,
    this.adminOverrideAt,
    this.branchId,
  });

  final String id;
  final String technicianId;
  final String selfieUrl;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String status;
  final bool faceMatchPassed;
  final bool geofencePassed;
  final double? faceMatchScore;
  final String markedBy;
  final String? adminOverrideBy;
  final String? adminOverrideReason;
  final DateTime? adminOverrideAt;
  final String? branchId;

  factory Attendance.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Attendance(
      id: doc.id,
      technicianId: data['technicianId'] as String? ?? '',
      selfieUrl: data['selfieUrl'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] as String? ?? 'present',
      faceMatchPassed: data['faceMatchPassed'] as bool? ?? false,
      geofencePassed: data['geofencePassed'] as bool? ?? false,
      faceMatchScore: (data['faceMatchScore'] as num?)?.toDouble(),
      markedBy: data['markedBy'] as String? ?? 'technician',
      adminOverrideBy: data['adminOverrideBy'] as String?,
      adminOverrideReason: data['adminOverrideReason'] as String?,
      adminOverrideAt: (data['adminOverrideAt'] as Timestamp?)?.toDate(),
      branchId: data['branchId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'technicianId': technicianId,
        'selfieUrl': selfieUrl,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': Timestamp.fromDate(timestamp),
        'status': status,
        'faceMatchPassed': faceMatchPassed,
        'geofencePassed': geofencePassed,
        if (faceMatchScore != null) 'faceMatchScore': faceMatchScore,
        'markedBy': markedBy,
        if (branchId != null) 'branchId': branchId,
        if (adminOverrideBy != null) 'adminOverrideBy': adminOverrideBy,
        if (adminOverrideReason != null)
          'adminOverrideReason': adminOverrideReason,
        if (adminOverrideAt != null)
          'adminOverrideAt': Timestamp.fromDate(adminOverrideAt!),
      };
}
