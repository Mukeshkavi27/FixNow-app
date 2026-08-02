import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../domain/technician_incentive.dart';

final technicianIncentiveRepositoryProvider =
    Provider<TechnicianIncentiveRepository>((ref) {
  return TechnicianIncentiveRepository(
    ref.watch(firebaseRefsProvider).firestore,
  );
});

final technicianIncentivesProvider = StreamProvider.autoDispose
    .family<List<TechnicianIncentive>, String>((ref, technicianId) {
  return ref
      .watch(technicianIncentiveRepositoryProvider)
      .watchForTechnician(technicianId);
});

class TechnicianIncentiveRepository {
  TechnicianIncentiveRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<TechnicianIncentive>> watchForTechnician(String technicianId) {
    return _firestore
        .collection('technician_incentives')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(TechnicianIncentive.fromFirestore)
          .toList()
        ..sort((left, right) => right.awardedAt.compareTo(left.awardedAt));
      return items;
    });
  }

  Stream<List<TechnicianIncentive>> watchAll({String? revenueBranchId}) {
    if (revenueBranchId == null || revenueBranchId.isEmpty) {
      return _firestore.collection('technician_incentives').snapshots().map(
            (snapshot) => _sort(
              snapshot.docs.map(TechnicianIncentive.fromFirestore).toList(),
            ),
          );
    }
    final revenueQuery = _firestore
        .collection('technician_incentives')
        .where('revenueBranchId', isEqualTo: revenueBranchId)
        .snapshots();
    final legacyQuery = _firestore
        .collection('technician_incentives')
        .where('branchId', isEqualTo: revenueBranchId)
        .snapshots();
    final controller = StreamController<List<TechnicianIncentive>>();
    List<TechnicianIncentive>? revenueItems;
    List<TechnicianIncentive>? legacyItems;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? revenueSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? legacySub;

    void emit() {
      if (revenueItems == null || legacyItems == null) return;
      final byId = <String, TechnicianIncentive>{
        for (final item in legacyItems!) item.id: item,
        for (final item in revenueItems!) item.id: item,
      };
      controller.add(_sort(byId.values.toList()));
    }

    controller.onListen = () {
      revenueSub = revenueQuery.listen((snapshot) {
        revenueItems =
            snapshot.docs.map(TechnicianIncentive.fromFirestore).toList();
        emit();
      }, onError: controller.addError);
      legacySub = legacyQuery.listen((snapshot) {
        legacyItems =
            snapshot.docs.map(TechnicianIncentive.fromFirestore).toList();
        emit();
      }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await revenueSub?.cancel();
      await legacySub?.cancel();
    };
    return controller.stream;
  }

  List<TechnicianIncentive> _sort(List<TechnicianIncentive> items) {
    items.sort((left, right) => right.awardedAt.compareTo(left.awardedAt));
    return items;
  }

  Future<void> addIncentive({
    required String technicianId,
    required String branchId,
    required String revenueBranchId,
    required double amount,
    required String description,
    required String awardedBy,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Enter an incentive greater than zero.');
    }
    final reason = description.trim();
    if (reason.length < 3) {
      throw ArgumentError('Enter a short incentive reason.');
    }
    await _firestore.collection('technician_incentives').add({
      'technicianId': technicianId,
      'branchId': branchId,
      'revenueBranchId': revenueBranchId,
      'amount': amount,
      'description': reason,
      'awardedBy': awardedBy,
      'awardedAt': FieldValue.serverTimestamp(),
    });
  }
}
