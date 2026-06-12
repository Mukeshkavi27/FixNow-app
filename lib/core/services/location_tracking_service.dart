import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/technician/data/technician_repository.dart';
import '../../features/technician/domain/technician_location.dart';

final locationTrackingServiceProvider =
    Provider<LocationTrackingService>((ref) {
  final service = LocationTrackingService(
    ref.watch(technicianRepositoryProvider),
  );
  ref.onDispose(service.stop);
  return service;
});

class LocationTrackingService {
  LocationTrackingService(this._repository);

  final TechnicianRepository _repository;
  StreamSubscription<Position>? _subscription;
  String? _activeBookingId;

  bool get isTracking => _subscription != null;
  String? get activeBookingId => _activeBookingId;

  Future<void> start({
    required String technicianId,
    required String bookingId,
  }) async {
    await stop();
    final permission = await _ensurePermission();
    if (!permission) {
      throw StateError('Location permission is required for live tracking.');
    }
    _activeBookingId = bookingId;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
    );
    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) {
      _repository.updateLocation(
        TechnicianLocation(
          technicianId: technicianId,
          latitude: position.latitude,
          longitude: position.longitude,
          updatedAt: DateTime.now(),
          activeBookingId: bookingId,
        ),
      );
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _activeBookingId = null;
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
