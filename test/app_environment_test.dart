import 'package:fixnow/core/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('development still requires an explicit service URL', () {
    expect(AppEnvironment.isDevelopment, isTrue);
    expect(
      () => AppEnvironment.requireServiceUrl('', name: 'TEST_URL'),
      throwsUnsupportedError,
    );
  });

  test('service URL validation rejects malformed URLs', () {
    expect(
      () => AppEnvironment.requireServiceUrl('not-a-url', name: 'TEST_URL'),
      throwsUnsupportedError,
    );
  });
}
