import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/firebase_providers.dart';

final serviceCatalogRepositoryProvider =
    Provider<ServiceCatalogRepository>((ref) {
  return ServiceCatalogRepository(ref.watch(firebaseRefsProvider).firestore);
});

final serviceCatalogProvider =
    StreamProvider.autoDispose<List<ApplianceCategory>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).watchServices();
});

class ServiceCatalogRepository {
  ServiceCatalogRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<ApplianceCategory>> watchServices() {
    return _firestore
        .collection('services')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final services = snapshot.docs.map((doc) {
        final data = doc.data();
        return ApplianceCategory(
          data['name'] as String? ?? doc.id,
          data['startingPriceLabel'] as String? ??
              'Starting at Rs. ${(data['startingPrice'] as num?)?.toInt() ?? 0}',
          data['assetName'] as String? ?? '',
          imageUrl: data['imageUrl'] as String?,
          startingPriceValue: (data['startingPrice'] as num?)?.toDouble(),
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return services.isEmpty ? AppConstants.applianceCategories : services;
    });
  }
}
