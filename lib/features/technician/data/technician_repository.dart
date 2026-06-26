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

  Stream<List<Attendance>> watchAttendance() {
    return _firestore
        .collection('attendance')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Attendance.fromFirestore).toList());
  }

  Future<void> updateLocation(TechnicianLocation location) {
    return _firestore
        .collection('technician_locations')
        .doc(location.technicianId)
        .set(location.toJson(), SetOptions(merge: true));
  }

  Future<void> stopSharingLocation(String technicianId) {
    return _firestore
        .collection('technician_locations')
        .doc(technicianId)
        .update({
      'activeBookingId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
