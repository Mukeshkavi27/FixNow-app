import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../maps/google_maps_config.dart';

final reverseGeocodingServiceProvider = Provider<ReverseGeocodingService>(
  (ref) {
    final fallback = NominatimReverseGeocodingService();
    if (!GoogleMapsConfig.isConfigured) return fallback;
    return FallbackReverseGeocodingService([
      GoogleReverseGeocodingService(apiKey: GoogleMapsConfig.apiKey),
      fallback,
    ]);
  },
);

final addressGeocodingServiceProvider = Provider<AddressGeocodingService>(
  (ref) {
    final fallback = NominatimAddressGeocodingService();
    if (!GoogleMapsConfig.isConfigured) return fallback;
    return FallbackAddressGeocodingService([
      GoogleAddressGeocodingService(apiKey: GoogleMapsConfig.apiKey),
      fallback,
    ]);
  },
);

final addressSearchServiceProvider = Provider<AddressSearchService>(
  (ref) {
    final fallback = NominatimAddressSearchService();
    if (!GoogleMapsConfig.isConfigured) return fallback;
    return FallbackAddressSearchService([
      GooglePlacesAddressSearchService(apiKey: GoogleMapsConfig.apiKey),
      fallback,
    ]);
  },
);

class ReverseGeocodingResult {
  const ReverseGeocodingResult({
    required this.address,
    required this.provider,
  });

  final String address;
  final String provider;
}

class AddressGeocodingResult {
  const AddressGeocodingResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.provider,
    this.placeId,
    this.house,
    this.street,
    this.locality,
    this.landmark,
    this.city,
    this.state,
    this.pincode,
    this.serviceArea,
  });

  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String provider;
  final String? placeId;
  final String? house;
  final String? street;
  final String? locality;
  final String? landmark;
  final String? city;
  final String? state;
  final String? pincode;
  final String? serviceArea;

  String get displayAddress {
    final parts = <String>[
      if ((house ?? '').trim().isNotEmpty) house!.trim(),
      if ((street ?? '').trim().isNotEmpty) street!.trim(),
      if ((locality ?? '').trim().isNotEmpty) locality!.trim(),
      if ((city ?? '').trim().isNotEmpty && (pincode ?? '').trim().isNotEmpty)
        '${city!.trim()} - ${pincode!.trim()}'
      else if ((city ?? '').trim().isNotEmpty)
        city!.trim()
      else if ((pincode ?? '').trim().isNotEmpty)
        pincode!.trim(),
      if ((state ?? '').trim().isNotEmpty) state!.trim(),
    ];
    return parts.isEmpty ? formattedAddress : _dedupeAddressParts(parts);
  }
}

class AddressSearchSuggestion {
  const AddressSearchSuggestion({
    required this.title,
    required this.subtitle,
    required this.provider,
    this.placeId,
    this.latitude,
    this.longitude,
  });

  final String title;
  final String subtitle;
  final String provider;
  final String? placeId;
  final double? latitude;
  final double? longitude;
}

abstract class ReverseGeocodingService {
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  });
}

abstract class AddressGeocodingService {
  Future<AddressGeocodingResult?> search(String address);
}

abstract class AddressSearchService {
  Future<List<AddressSearchSuggestion>> suggestions(String input);
  Future<AddressGeocodingResult?> resolve(AddressSearchSuggestion suggestion);
}

class FallbackReverseGeocodingService implements ReverseGeocodingService {
  const FallbackReverseGeocodingService(this.services);

  final List<ReverseGeocodingService> services;

  @override
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    for (final service in services) {
      try {
        final result = await service.reverse(
          latitude: latitude,
          longitude: longitude,
        );
        if (result != null) return result;
      } catch (_) {
        // Try the next provider so booking does not fail on map API issues.
      }
    }
    return null;
  }
}

class FallbackAddressGeocodingService implements AddressGeocodingService {
  const FallbackAddressGeocodingService(this.services);

  final List<AddressGeocodingService> services;

  @override
  Future<AddressGeocodingResult?> search(String address) async {
    for (final service in services) {
      try {
        final result = await service.search(address);
        if (result != null) return result;
      } catch (_) {
        // Try the next provider so booking can still continue.
      }
    }
    return null;
  }
}

class FallbackAddressSearchService implements AddressSearchService {
  const FallbackAddressSearchService(this.services);

  final List<AddressSearchService> services;

  @override
  Future<List<AddressSearchSuggestion>> suggestions(String input) async {
    for (final service in services) {
      try {
        final result = await service.suggestions(input);
        if (result.isNotEmpty) return result;
      } catch (_) {}
    }
    return const [];
  }

  @override
  Future<AddressGeocodingResult?> resolve(
    AddressSearchSuggestion suggestion,
  ) async {
    for (final service in services) {
      if (suggestion.provider != service.runtimeType.toString() &&
          suggestion.provider != 'Google Places API' &&
          suggestion.provider != 'OpenStreetMap Nominatim') {
        continue;
      }
      try {
        final result = await service.resolve(suggestion);
        if (result != null) return result;
      } catch (_) {}
    }
    return null;
  }
}

class GoogleReverseGeocodingService implements ReverseGeocodingService {
  GoogleReverseGeocodingService({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  @override
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey.trim().isEmpty) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '${latitude.toStringAsFixed(7)},${longitude.toStringAsFixed(7)}',
      'key': _apiKey,
    });

    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final results = data['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) return null;
    final first = results.first;
    if (first is! Map<String, dynamic>) return null;
    final address = first['formatted_address'] as String?;
    if (address == null || address.trim().isEmpty) return null;

    return ReverseGeocodingResult(
      address: address.trim(),
      provider: 'Google Maps Geocoding API',
    );
  }
}

class GoogleAddressGeocodingService implements AddressGeocodingService {
  GoogleAddressGeocodingService({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  @override
  Future<AddressGeocodingResult?> search(String address) async {
    if (_apiKey.trim().isEmpty || address.trim().isEmpty) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address.trim(),
      'key': _apiKey,
    });

    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final results = data['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) return null;
    final first = results.first;
    if (first is! Map<String, dynamic>) return null;
    final geometry = first['geometry'] as Map<String, dynamic>? ?? const {};
    final location = geometry['location'] as Map<String, dynamic>? ?? const {};
    final latitude = (location['lat'] as num?)?.toDouble();
    final longitude = (location['lng'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final parts = _googleAddressParts(
      first['address_components'] as List<dynamic>?,
    );
    return AddressGeocodingResult(
      latitude: latitude,
      longitude: longitude,
      formattedAddress:
          (first['formatted_address'] as String?)?.trim() ?? address.trim(),
      provider: 'Google Maps Geocoding API',
      placeId: first['place_id'] as String?,
      house: parts['house'],
      street: parts['street'],
      locality: parts['locality'],
      city: parts['city'],
      state: parts['state'],
      pincode: parts['pincode'],
      serviceArea: parts['serviceArea'],
    );
  }
}

class GooglePlacesAddressSearchService implements AddressSearchService {
  GooglePlacesAddressSearchService({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  @override
  Future<List<AddressSearchSuggestion>> suggestions(String input) async {
    if (_apiKey.trim().isEmpty || input.trim().length < 3) return const [];
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': input.trim(),
        'key': _apiKey,
        'components': 'country:in',
      },
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return const [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
      return const [];
    }
    final predictions = data['predictions'] as List<dynamic>? ?? const [];
    return predictions.whereType<Map<String, dynamic>>().map((item) {
      final structured =
          item['structured_formatting'] as Map<String, dynamic>? ?? const {};
      return AddressSearchSuggestion(
        title: (structured['main_text'] as String?) ??
            (item['description'] as String? ?? 'Address'),
        subtitle: (structured['secondary_text'] as String?) ??
            (item['description'] as String? ?? ''),
        placeId: item['place_id'] as String?,
        provider: 'Google Places API',
      );
    }).toList();
  }

  @override
  Future<AddressGeocodingResult?> resolve(
    AddressSearchSuggestion suggestion,
  ) async {
    final placeId = suggestion.placeId;
    if (_apiKey.trim().isEmpty || placeId == null || placeId.isEmpty) {
      return null;
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'key': _apiKey,
      'fields': 'place_id,formatted_address,geometry,address_component,name',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    final geometry = result['geometry'] as Map<String, dynamic>? ?? const {};
    final location = geometry['location'] as Map<String, dynamic>? ?? const {};
    final latitude = (location['lat'] as num?)?.toDouble();
    final longitude = (location['lng'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final parts = _googleAddressParts(
      result['address_components'] as List<dynamic>?,
    );
    return AddressGeocodingResult(
      latitude: latitude,
      longitude: longitude,
      formattedAddress:
          (result['formatted_address'] as String?)?.trim() ?? suggestion.title,
      provider: 'Google Places API',
      placeId: result['place_id'] as String? ?? placeId,
      landmark: result['name'] as String?,
      house: parts['house'],
      street: parts['street'],
      locality: parts['locality'],
      city: parts['city'],
      state: parts['state'],
      pincode: parts['pincode'],
      serviceArea: parts['serviceArea'],
    );
  }
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

class NominatimAddressGeocodingService implements AddressGeocodingService {
  NominatimAddressGeocodingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<AddressGeocodingResult?> search(String address) async {
    if (address.trim().isEmpty) return null;
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': address.trim(),
      'limit': '1',
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

    final decoded = jsonDecode(response.body);
    final results = decoded is List<dynamic> ? decoded : const <dynamic>[];
    if (results.isEmpty || results.first is! Map<String, dynamic>) return null;
    final first = results.first as Map<String, dynamic>;
    final latitude = double.tryParse(first['lat'] as String? ?? '');
    final longitude = double.tryParse(first['lon'] as String? ?? '');
    if (latitude == null || longitude == null) return null;
    final parts = _nominatimAddressParts(first['address'] as Map<String, dynamic>?);
    return AddressGeocodingResult(
      latitude: latitude,
      longitude: longitude,
      formattedAddress:
          (first['display_name'] as String?)?.trim() ?? address.trim(),
      provider: 'OpenStreetMap Nominatim',
      placeId: first['place_id']?.toString(),
      house: parts['house'],
      street: parts['street'],
      locality: parts['locality'],
      city: parts['city'],
      state: parts['state'],
      pincode: parts['pincode'],
      serviceArea: parts['serviceArea'],
    );
  }
}

class NominatimAddressSearchService implements AddressSearchService {
  NominatimAddressSearchService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<AddressSearchSuggestion>> suggestions(String input) async {
    if (input.trim().length < 3) return const [];
    final results = await _searchRaw(input);
    return results.map((item) {
      final address = item['address'] as Map<String, dynamic>? ?? const {};
      final title = (item['name'] as String?) ??
          (address['road'] as String?) ??
          input.trim();
      return AddressSearchSuggestion(
        title: title,
        subtitle: item['display_name'] as String? ?? '',
        provider: 'OpenStreetMap Nominatim',
        placeId: item['place_id']?.toString(),
        latitude: double.tryParse(item['lat'] as String? ?? ''),
        longitude: double.tryParse(item['lon'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  Future<AddressGeocodingResult?> resolve(
    AddressSearchSuggestion suggestion,
  ) async {
    if (suggestion.latitude == null || suggestion.longitude == null) {
      return null;
    }
    final geocoded = await NominatimAddressGeocodingService(client: _client)
        .search(suggestion.subtitle.isEmpty ? suggestion.title : suggestion.subtitle);
    if (geocoded != null) return geocoded;
    final reversed = await NominatimReverseGeocodingService(client: _client)
        .reverse(
          latitude: suggestion.latitude!,
          longitude: suggestion.longitude!,
        );
    if (reversed == null) return null;
    return AddressGeocodingResult(
      latitude: suggestion.latitude!,
      longitude: suggestion.longitude!,
      formattedAddress: reversed.address,
      provider: reversed.provider,
      placeId: suggestion.placeId,
    );
  }

  Future<List<Map<String, dynamic>>> _searchRaw(String input) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': input.trim(),
      'limit': '6',
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
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
}

Map<String, String?> _googleAddressParts(List<dynamic>? components) {
  String? byType(String type) {
    for (final item in components ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      final types = item['types'] as List<dynamic>? ?? const [];
      if (types.contains(type)) return item['long_name'] as String?;
    }
    return null;
  }

  final house = [
    byType('street_number'),
    byType('premise'),
    byType('subpremise'),
  ].where((item) => (item ?? '').trim().isNotEmpty).join(', ');
  final locality = byType('sublocality_level_1') ??
      byType('sublocality') ??
      byType('neighborhood');
  return {
    'house': house.isEmpty ? null : house,
    'street': byType('route'),
    'locality': locality,
    'city': byType('locality') ?? byType('administrative_area_level_3'),
    'state': byType('administrative_area_level_1'),
    'pincode': byType('postal_code'),
    'serviceArea': locality,
  };
}

Map<String, String?> _nominatimAddressParts(Map<String, dynamic>? address) {
  final data = address ?? const <String, dynamic>{};
  String? pick(List<String> keys) {
    for (final key in keys) {
      final value = data[key] as String?;
      if ((value ?? '').trim().isNotEmpty) return value!.trim();
    }
    return null;
  }

  final locality = pick(['suburb', 'neighbourhood', 'quarter', 'city_district']);
  return {
    'house': pick(['house_number', 'building']),
    'street': pick(['road', 'pedestrian', 'footway']),
    'locality': locality,
    'city': pick(['city', 'town', 'village', 'municipality', 'county']),
    'state': pick(['state']),
    'pincode': pick(['postcode']),
    'serviceArea': locality,
  };
}

String _dedupeAddressParts(List<String> parts) {
  final seen = <String>{};
  final filtered = <String>[];
  for (final part in parts) {
    final key = part.toLowerCase();
    if (seen.add(key)) filtered.add(part);
  }
  return filtered.join(', ');
}
