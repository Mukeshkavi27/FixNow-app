import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/attendance.dart';
import '../domain/overtime_record.dart';
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
    required String branchId,
  }) {
    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _firestore
        .collection('attendance')
        .doc('${technicianId}_$dayKey')
        .set({
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
      'branchId': branchId,
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 20));
  }

  Stream<List<Attendance>> watchAttendance({String? branchId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('attendance');
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query
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

  Future<void> updateLocation(TechnicianLocation location) async {
    final technicianRef = _firestore
        .collection('technician_locations')
        .doc(location.technicianId);
    final historyRef = technicianRef.collection('history').doc();
    if (isTechnicianOvertime(location.updatedAt) &&
        (location.branchId ?? '').isNotEmpty) {
      await _persistOvertimeLocation(
        location: location,
        technicianRef: technicianRef,
        historyRef: historyRef,
      );
      return;
    }
    final batch = _firestore.batch();
    batch.set(technicianRef, location.toJson(), SetOptions(merge: true));
    batch.set(historyRef, location.toJson());
    await batch.commit();
  }

  Future<void> _persistOvertimeLocation({
    required TechnicianLocation location,
    required DocumentReference<Map<String, dynamic>> technicianRef,
    required DocumentReference<Map<String, dynamic>> historyRef,
  }) async {
    final dateKey = overtimeDayKey(location.updatedAt);
    final overtimeRef = _firestore
        .collection('technician_overtime')
        .doc('${location.technicianId}_$dateKey');
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(overtimeRef);
      transaction.set(
          technicianRef, location.toJson(), SetOptions(merge: true));
      transaction.set(historyRef, location.toJson());
      transaction.set(
          overtimeRef,
          {
            'technicianId': location.technicianId,
            'branchId': location.branchId,
            'dateKey': dateKey,
            if (!existing.exists) 'startedAt': FieldValue.serverTimestamp(),
            'lastDetectedAt': FieldValue.serverTimestamp(),
            'isActive': true,
            'extraBookingIds': location.activeBookingId == null
                ? (existing.data()?['extraBookingIds'] ?? <String>[])
                : FieldValue.arrayUnion([location.activeBookingId]),
          },
          SetOptions(merge: true));
      if (!existing.exists) {
        _createOvertimeNotifications(
          transaction: transaction,
          location: location,
          dateKey: dateKey,
        );
      }
    });
  }

  void _createOvertimeNotifications({
    required Transaction transaction,
    required TechnicianLocation location,
    required String dateKey,
  }) {
    final notificationBase = {
      'technicianId': location.technicianId,
      'branchId': location.branchId,
      'dateKey': dateKey,
      'type': 'technicianOvertimeStarted',
      'title': 'Working Overtime',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    transaction.set(
      _firestore
          .collection('notifications')
          .doc('overtime_${location.technicianId}_${dateKey}_technician'),
      {
        ...notificationBase,
        'userId': location.technicianId,
        'recipientRole': 'technician',
        'body': 'Work after 10:00 PM is now being recorded as overtime.',
      },
    );
    transaction.set(
      _firestore
          .collection('notifications')
          .doc('overtime_${location.technicianId}_${dateKey}_branch'),
      {
        ...notificationBase,
        'userId': 'branch:${location.branchId}',
        'recipientRole': 'branchAdmin',
        'body': 'A branch technician started working after 10:00 PM.',
      },
    );
    transaction.set(
      _firestore
          .collection('notifications')
          .doc('overtime_${location.technicianId}_${dateKey}_super'),
      {
        ...notificationBase,
        'userId': 'role:superAdmin',
        'recipientRole': 'superAdmin',
        'body': 'A technician started working after 10:00 PM.',
      },
    );
  }

  Future<void> clearActiveBooking(String technicianId) {
    return _firestore.collection('technician_locations').doc(technicianId).set({
      'activeBookingId': FieldValue.delete(),
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> stopSharingLocation(String technicianId) {
    return _firestore.collection('technician_locations').doc(technicianId).set({
      'activeBookingId': FieldValue.delete(),
      'isOnline': false,
      'speed': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> closeOvertime(String technicianId, String dateKey) async {
    final overtimeRef = _firestore
        .collection('technician_overtime')
        .doc('${technicianId}_$dateKey');
    try {
      await overtimeRef.update({
        'isActive': false,
        'lastDetectedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
    }
  }

  Stream<TechnicianLocation?> watchLocation(String technicianId) {
    return _firestore
        .collection('technician_locations')
        .doc(technicianId)
        .snapshots()
        .map(
            (doc) => doc.exists ? TechnicianLocation.fromFirestore(doc) : null);
  }

  Stream<List<TechnicianLocation>> watchActiveLocations({String? branchId}) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('technician_locations');
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(TechnicianLocation.fromFirestore).toList(),
        );
  }

  Stream<List<TechnicianLocation>> watchTravelHistory(
    String technicianId, {
    int limit = 5000,
  }) {
    return _firestore
        .collection('technician_locations')
        .doc(technicianId)
        .collection('history')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final points = snapshot.docs
          .map(TechnicianLocation.fromFirestore)
          .toList()
        ..sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
      return points;
    });
  }

  Stream<List<OvertimeRecord>> watchOvertime({String? branchId}) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('technician_overtime');
    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query.snapshots().map((snapshot) {
      final records = snapshot.docs.map(OvertimeRecord.fromFirestore).toList()
        ..sort(
          (left, right) => right.lastDetectedAt.compareTo(left.lastDetectedAt),
        );
      return records;
    });
  }

  Stream<List<OvertimeRecord>> watchTechnicianOvertime(String technicianId) {
    return _firestore
        .collection('technician_overtime')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snapshot) {
      final records = snapshot.docs.map(OvertimeRecord.fromFirestore).toList()
        ..sort(
          (left, right) => right.lastDetectedAt.compareTo(left.lastDetectedAt),
        );
      return records;
    });
  }
}
