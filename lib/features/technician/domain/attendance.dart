import 'package:cloud_firestore/cloud_firestore.dart';

class Attendance {
  const Attendance({
    required this.id,
    required this.technicianId,
    required this.selfieUrl,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.faceMatchPassed = false,
    this.geofencePassed = false,
  });

  final String id;
  final String technicianId;
  final String selfieUrl;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool faceMatchPassed;
  final bool geofencePassed;

  factory Attendance.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Attendance(
      id: doc.id,
      technicianId: data['technicianId'] as String? ?? '',
      selfieUrl: data['selfieUrl'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      faceMatchPassed: data['faceMatchPassed'] as bool? ?? false,
      geofencePassed: data['geofencePassed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'technicianId': technicianId,
        'selfieUrl': selfieUrl,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': Timestamp.fromDate(timestamp),
        'faceMatchPassed': faceMatchPassed,
        'geofencePassed': geofencePassed,
      };
}
