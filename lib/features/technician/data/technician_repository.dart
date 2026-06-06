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
    return _firestore.collection('attendance').add(attendance.toJson());
  }

  Future<void> updateLocation(TechnicianLocation location) {
    return _firestore
        .collection('technician_locations')
        .doc(location.technicianId)
        .set(location.toJson(), SetOptions(merge: true));
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchActiveLocations() {
    return _firestore.collection('technician_locations').snapshots().map((snap) => snap.docs);
  }
}
