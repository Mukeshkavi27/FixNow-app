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
  Timer? _timer;
  bool _sending = false;
  String? _technicianId;
  String? _activeBookingId;

  bool get isTracking => _timer != null;
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
    _technicianId = technicianId;
    _activeBookingId = bookingId;
    await _sendCurrentPosition(
      technicianId: technicianId,
      bookingId: bookingId,
    );
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendCurrentPosition(
        technicianId: technicianId,
        bookingId: bookingId,
      );
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final technicianId = _technicianId;
    if (technicianId != null) {
      await _repository.stopSharingLocation(technicianId);
    }
    _technicianId = null;
    _activeBookingId = null;
  }

  Future<void> _sendCurrentPosition({
    required String technicianId,
    required String bookingId,
  }) async {
    if (_sending) return;
    _sending = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 8));
      await _repository.updateLocation(
        TechnicianLocation(
          technicianId: technicianId,
          latitude: position.latitude,
          longitude: position.longitude,
          updatedAt: DateTime.now(),
          activeBookingId: bookingId,
          heading: position.heading.isNaN ? null : position.heading,
          bearing: position.heading.isNaN ? null : position.heading,
          speed: position.speed.isNaN ? null : position.speed,
          accuracy: position.accuracy.isNaN ? null : position.accuracy,
          isOnline: true,
        ),
      );
    } finally {
      _sending = false;
    }
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
