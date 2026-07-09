import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/attendance.dart';
import '../domain/technician_location.dart';

final technicianRepositoryProvider = Provider<TechnicianRepository>((ref) {
  return TechnicianRepository(ref.watch(firebaseRefsProvider).firestore);
});

class TechnicianRepository {
  TechnicianRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> markAttendance(Attendance attendance) {
    final day = attendance.timestamp;
    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _firestore
        .collection('attendance')
        .doc('${attendance.technicianId}_$dayKey')
        .set({
      ...attendance.toJson(),
      'timestamp': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
  }

  Future<void> adminOverrideAttendance({
    required String technicianId,
    required DateTime day,
    required String status,
    required String adminId,
    required String reason,
  }) {
    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _firestore.collection('attendance').doc('${technicianId}_$dayKey').set({
      'technicianId': technicianId,
      'selfieUrl': '',
      'latitude': 0,
      'longitude': 0,
      'timestamp': Timestamp.fromDate(DateTime(day.year, day.month, day.day)),
      'status': status,
      'faceMatchPassed': true,
      'geofencePassed': true,
      'markedBy': 'admin',
      'adminOverrideBy': adminId,
      'adminOverrideReason': reason.trim(),
      'adminOverrideAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 20));
  }

  Stream<List<Attendance>> watchAttendance() {
    return _firestore
        .collection('attendance')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Attendance.fromFirestore).toList());
  }

  Stream<List<Attendance>> watchTechnicianAttendance(String technicianId) {
    return _firestore
        .collection('attendance')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snap) {
      final records = snap.docs.map(Attendance.fromFirestore).toList()
        ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
      return records;
    });
  }

  Future<void> updateLocation(TechnicianLocation location) {
    return _firestore
        .collection('technician_locations')
        .doc(location.technicianId)
        .set(location.toJson(), SetOptions(merge: true));
  }

  Future<void> stopSharingLocation(String technicianId) {
    return _firestore.collection('technician_locations').doc(technicianId).set({
      'activeBookingId': FieldValue.delete(),
      'isOnline': false,
      'speed': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<TechnicianLocation?> watchLocation(String technicianId) {
    return _firestore
        .collection('technician_locations')
        .doc(technicianId)
        .snapshots()
        .map(
            (doc) => doc.exists ? TechnicianLocation.fromFirestore(doc) : null);
  }

  Stream<List<TechnicianLocation>> watchActiveLocations() {
    return _firestore.collection('technician_locations').snapshots().map(
          (snap) => snap.docs.map(TechnicianLocation.fromFirestore).toList(),
        );
  }
}
