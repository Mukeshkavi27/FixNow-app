import 'package:flutter/foundation.dart';

enum FixNowEnvironment { development, staging, production }

class AppEnvironment {
  const AppEnvironment._();

  static const _configuredName = String.fromEnvironment(
    'FIXNOW_ENVIRONMENT',
    defaultValue: '',
  );

  static FixNowEnvironment get current {
    final value = _configuredName.isEmpty
        ? (kDebugMode ? 'development' : 'production')
        : _configuredName.trim().toLowerCase();
    return switch (value) {
      'development' => FixNowEnvironment.development,
      'staging' => FixNowEnvironment.staging,
      'production' => FixNowEnvironment.production,
      _ => throw UnsupportedError(
          'Invalid FIXNOW_ENVIRONMENT "$value". Use development, staging, or production.',
        ),
    };
  }

  static bool get isDevelopment => current == FixNowEnvironment.development;

  static String requireServiceUrl(String configured, {required String name}) {
    final value = configured.trim();
    if (value.isEmpty) {
      throw UnsupportedError('$name must be provided for this build.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || !uri.hasScheme) {
      throw UnsupportedError('$name is not a valid URL.');
    }
    final isLoopback = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (!isDevelopment && (uri.scheme != 'https' || isLoopback)) {
      throw UnsupportedError(
          '$name must be a public HTTPS URL outside development.');
    }
    return value.replaceFirst(RegExp(r'/$'), '');
  }
}
