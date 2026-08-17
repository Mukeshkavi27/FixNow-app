import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const _cloudinaryCloudName = 'mxdofr6e';
const _paymentProofUploadPreset = 'fixnow_payment_proofs';

final cloudinaryRepositoryProvider = Provider<CloudinaryRepository>((ref) {
  return CloudinaryRepository();
});

class CloudinaryRepository {
  CloudinaryRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> uploadCustomerPhoto({
    required XFile file,
    required String bookingId,
  }) {
    return _uploadImage(
      file: file,
      bookingId: bookingId,
      emptyMessage: 'The selected customer photo is empty.',
      sizeMessage: 'Customer photo must be smaller than 5 MB.',
      failureMessage: 'Customer photo upload failed. Please try again.',
    );
  }

  Future<String> uploadPaymentProof({
    required XFile file,
    required String bookingId,
  }) {
    return _uploadImage(
      file: file,
      bookingId: bookingId,
      emptyMessage: 'The selected screenshot is empty.',
      sizeMessage: 'Payment screenshot must be smaller than 5 MB.',
      failureMessage: 'Payment screenshot upload failed. Please try again.',
    );
  }

  Future<String> _uploadImage({
    required XFile file,
    required String bookingId,
    required String emptyMessage,
    required String sizeMessage,
    required String failureMessage,
  }) async {
    if (bookingId.trim().isEmpty) throw ArgumentError('Booking ID is required.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError(emptyMessage);
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError(sizeMessage);
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.https(
        'api.cloudinary.com',
        '/v1_1/$_cloudinaryCloudName/image/upload',
      ),
    )
      ..fields['upload_preset'] = _paymentProofUploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isEmpty ? 'payment-proof.jpg' : file.name,
        ),
      );

    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 45),
        );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(failureMessage);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = json['secure_url'] as String?;
    final uri = secureUrl == null ? null : Uri.tryParse(secureUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com') {
      throw StateError('Cloudinary returned an invalid screenshot URL.');
    }
    return secureUrl!;
  }
}
