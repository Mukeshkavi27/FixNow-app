import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final reverseGeocodingServiceProvider = Provider<ReverseGeocodingService>(
  (ref) => NominatimReverseGeocodingService(),
);

class ReverseGeocodingResult {
  const ReverseGeocodingResult({
    required this.address,
    required this.provider,
  });

  final String address;
  final String provider;
}

abstract class ReverseGeocodingService {
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  });
}

class NominatimReverseGeocodingService implements ReverseGeocodingService {
  NominatimReverseGeocodingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toStringAsFixed(7),
      'lon': longitude.toStringAsFixed(7),
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'en',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': 'FixNow/1.0 support@fixnow.local',
    };

    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName = data['display_name'] as String?;
    if (displayName == null || displayName.trim().isEmpty) return null;

    return ReverseGeocodingResult(
      address: displayName.trim(),
      provider: 'OpenStreetMap Nominatim',
    );
  }
}

// Production swap point:
// Replace reverseGeocodingServiceProvider with a Google Geocoding implementation
// that calls your backend or Google Maps Platform key-protected endpoint.
