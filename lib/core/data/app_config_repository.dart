import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firebase_providers.dart';

final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository(ref.watch(firebaseRefsProvider).firestore);
});

final operationsConfigProvider =
    StreamProvider.autoDispose<OperationsConfig>((ref) {
  return ref.watch(appConfigRepositoryProvider).watchOperationsConfig();
});

class AppConfigRepository {
  AppConfigRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<OperationsConfig> watchOperationsConfig() {
    return _firestore.collection('app_config').doc('operations').snapshots().map(
          (doc) => OperationsConfig.fromJson(doc.data() ?? const {}),
        );
  }
}

class OperationsConfig {
  const OperationsConfig({
    required this.branchLatitude,
    required this.branchLongitude,
    required this.geofenceRadiusMeters,
    required this.attendanceStartHour,
    required this.attendanceStartMinute,
    required this.attendanceEndHour,
    required this.attendanceEndMinute,
    required this.whatsappApprovalNumber,
  });

  final double branchLatitude;
  final double branchLongitude;
  final double geofenceRadiusMeters;
  final int attendanceStartHour;
  final int attendanceStartMinute;
  final int attendanceEndHour;
  final int attendanceEndMinute;
  final String whatsappApprovalNumber;

  factory OperationsConfig.fromJson(Map<String, dynamic> data) {
    return OperationsConfig(
      branchLatitude: (data['branchLatitude'] as num?)?.toDouble() ?? 13.0827,
      branchLongitude: (data['branchLongitude'] as num?)?.toDouble() ?? 80.2707,
      geofenceRadiusMeters:
          (data['geofenceRadiusMeters'] as num?)?.toDouble() ?? 250,
      attendanceStartHour: data['attendanceStartHour'] as int? ?? 9,
      attendanceStartMinute: data['attendanceStartMinute'] as int? ?? 15,
      attendanceEndHour: data['attendanceEndHour'] as int? ?? 9,
      attendanceEndMinute: data['attendanceEndMinute'] as int? ?? 45,
      whatsappApprovalNumber:
          data['whatsappApprovalNumber'] as String? ?? '+919999999999',
    );
  }

  DateTime startFor(DateTime day) {
    return DateTime(
      day.year,
      day.month,
      day.day,
      attendanceStartHour,
      attendanceStartMinute,
    );
  }

  DateTime endFor(DateTime day) {
    return DateTime(
      day.year,
      day.month,
      day.day,
      attendanceEndHour,
      attendanceEndMinute,
    );
  }
}
