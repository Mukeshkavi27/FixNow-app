import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(ref.watch(firebaseRefsProvider).storage);
});

class StorageRepository {
  StorageRepository(this._storage);

  final FirebaseStorage _storage;

  Future<String> uploadFile({
    required File file,
    required String folder,
    required String fileName,
  }) async {
    final ref = _storage.ref('$folder/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}
