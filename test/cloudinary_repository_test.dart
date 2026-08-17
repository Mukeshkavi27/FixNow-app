import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnow/features/shared/data/cloudinary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('uploads payment proof using the configured unsigned preset', () async {
    late http.Request captured;
    final repository = CloudinaryRepository(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'secure_url':
                'https://res.cloudinary.com/mxdofr6e/image/upload/proof.jpg',
          }),
          200,
        );
      }),
    );

    final result = await repository.uploadPaymentProof(
      file: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'proof.jpg'),
      bookingId: 'booking-1',
    );

    expect(captured.url.host, 'api.cloudinary.com');
    expect(captured.body, contains('fixnow_payment_proofs'));
    expect(result, startsWith('https://res.cloudinary.com/mxdofr6e/'));
  });

  test('rejects a non-Cloudinary upload response URL', () async {
    final repository = CloudinaryRepository(
      client: MockClient((_) async => http.Response(
            jsonEncode({'secure_url': 'https://example.com/proof.jpg'}),
            200,
          )),
    );

    expect(
      repository.uploadPaymentProof(
        file: XFile.fromData(Uint8List.fromList([1]), name: 'proof.jpg'),
        bookingId: 'booking-1',
      ),
      throwsStateError,
    );
  });

  test('uploads a customer booking photo through Cloudinary', () async {
    final repository = CloudinaryRepository(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'secure_url':
                  'https://res.cloudinary.com/mxdofr6e/image/upload/customer.jpg',
            }),
            200,
          )),
    );

    final result = await repository.uploadCustomerPhoto(
      file: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'customer.jpg'),
      bookingId: 'booking-1',
    );

    expect(result, contains('/customer.jpg'));
  });
}
