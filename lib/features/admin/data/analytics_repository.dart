import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(firebaseRefsProvider).firestore);
});

class AnalyticsRepository {
  AnalyticsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchDailyRevenue(
      String dayKey) {
    return _firestore.collection('analytics').doc('daily_$dayKey').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMonthlyRevenue(
      String monthKey) {
    return _firestore
        .collection('analytics')
        .doc('monthly_$monthKey')
        .snapshots();
  }
}
