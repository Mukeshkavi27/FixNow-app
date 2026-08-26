import 'package:fixnow/core/services/reverse_geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reverse geocoding cache reuses the same rounded coordinates', () async {
    final delegate = _FakeReverseGeocoder();
    final cache = CachedReverseGeocodingService(delegate);

    await cache.reverse(latitude: 11.016844, longitude: 76.955832);
    await cache.reverse(latitude: 11.0168441, longitude: 76.9558321);

    expect(delegate.calls, 1);
  });

  test('address geocoding cache ignores whitespace and letter case', () async {
    final delegate = _FakeAddressGeocoder();
    final cache = CachedAddressGeocodingService(delegate);

    await cache.search('  RS Puram  ');
    await cache.search('rs puram');

    expect(delegate.calls, 1);
  });

  test('address suggestion cache reuses an identical query', () async {
    final delegate = _FakeAddressSearch();
    final cache = CachedAddressSearchService(delegate);

    await cache.suggestions('Gandhipuram');
    await cache.suggestions(' gandhipuram ');

    expect(delegate.calls, 1);
  });
}

class _FakeReverseGeocoder implements ReverseGeocodingService {
  int calls = 0;

  @override
  Future<ReverseGeocodingResult?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    calls++;
    return const ReverseGeocodingResult(
      address: 'Coimbatore',
      provider: 'test',
    );
  }
}

class _FakeAddressGeocoder implements AddressGeocodingService {
  int calls = 0;

  @override
  Future<AddressGeocodingResult?> search(String address) async {
    calls++;
    return const AddressGeocodingResult(
      latitude: 11,
      longitude: 77,
      formattedAddress: 'RS Puram',
      provider: 'test',
    );
  }
}

class _FakeAddressSearch implements AddressSearchService {
  int calls = 0;

  @override
  Future<AddressGeocodingResult?> resolve(
    AddressSearchSuggestion suggestion,
  ) async =>
      null;

  @override
  Future<List<AddressSearchSuggestion>> suggestions(String input) async {
    calls++;
    return const [
      AddressSearchSuggestion(
        title: 'Gandhipuram',
        subtitle: 'Coimbatore',
        provider: 'test',
      ),
    ];
  }
}
