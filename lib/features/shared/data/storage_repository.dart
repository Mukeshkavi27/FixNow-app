import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/firebase_providers.dart';

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(ref.watch(firebaseRefsProvider).storage);
});

class StorageRepository {
  StorageRepository(this._storage);

  final FirebaseStorage _storage;

  Future<String> uploadXFile({
    required XFile file,
    required String folder,
    required String fileName,
  }) async {
    final ref = _storage.ref('$folder/$fileName');
    if (kIsWeb) {
      await ref
          .putData(
            await file.readAsBytes(),
            SettableMetadata(contentType: file.mimeType ?? 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 45));
    } else {
      await ref.putFile(File(file.path)).timeout(const Duration(seconds: 45));
    }
    return ref.getDownloadURL().timeout(const Duration(seconds: 20));
  }
}
