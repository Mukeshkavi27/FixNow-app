import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/technician/data/technician_repository.dart';
import '../../features/technician/domain/technician_location.dart';
import '../../features/technician/domain/overtime_record.dart';
import '../../features/technician/domain/technician_travel.dart';

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
  StreamSubscription<Position>? _positionSubscription;
  Timer? _startTimer;
  Timer? _endTimer;
  Timer? _gpsWatchdog;
  bool _sending = false;
  String? _technicianId;
  String? _activeBookingId;
  String? _branchId;
  String? _activeOvertimeDateKey;
  DateTime? _lastSuccessfulGpsAt;

  bool get isTracking =>
      _positionSubscription != null || _startTimer?.isActive == true;
  String? get activeBookingId => _activeBookingId;

  Future<void> start({
    required String technicianId,
    required String bookingId,
    String? branchId,
  }) {
    return startWorkingDay(
      technicianId: technicianId,
      branchId: branchId,
      bookingId: bookingId,
    );
  }

  Future<void> startWorkingDay({
    required String technicianId,
    String? branchId,
    String? bookingId,
  }) async {
    await stop();
    final permission = await _ensurePermission();
    if (!permission) {
      throw StateError(
        'Location permission is required for working-hours tracking.',
      );
    }

    final now = DateTime.now();
    final end = technicianTrackingDayEnd(now);

    _technicianId = technicianId;
    _activeBookingId = bookingId;
    _branchId = branchId;
    final start = technicianTrackingStart(now);
    if (now.isBefore(start)) {
      _startTimer = Timer(start.difference(now), _beginPositionStream);
    } else {
      await _beginPositionStream();
    }
    _endTimer = Timer(end.difference(now), stop);
  }

  Future<void> finishBooking() async {
    _activeBookingId = null;
    final technicianId = _technicianId;
    if (technicianId != null) {
      await _repository.clearActiveBooking(technicianId);
    }
  }

  Future<void> stop() async {
    _startTimer?.cancel();
    _startTimer = null;
    _endTimer?.cancel();
    _endTimer = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    final technicianId = _technicianId;
    if (technicianId != null) {
      final overtimeDateKey = _activeOvertimeDateKey;
      if (overtimeDateKey != null) {
        await _repository.closeOvertime(technicianId, overtimeDateKey);
      }
      await _repository.stopSharingLocation(technicianId);
    }
    _technicianId = null;
    _activeBookingId = null;
    _branchId = null;
    _activeOvertimeDateKey = null;
    _lastSuccessfulGpsAt = null;
  }

  Future<void> _beginPositionStream() async {
    _startTimer = null;
    final technicianId = _technicianId;
    if (technicianId == null ||
        !isWithinTechnicianTrackingDay(DateTime.now())) {
      return;
    }
    final settings = _locationSettings();
    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      ).timeout(const Duration(seconds: 12));
      await _publishPosition(initial);
    } catch (_) {
      // The continuous stream below retries when a GPS fix becomes available.
    }
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _publishPosition,
      onError: (_) {},
    );
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _recoverStaleGps(),
    );
  }

  Future<bool> recoverNow() async {
    if (_technicianId == null ||
        !isWithinTechnicianTrackingDay(DateTime.now())) {
      return false;
    }
    if (_sending) return true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings(),
      ).timeout(const Duration(seconds: 12));
      await _publishPosition(position);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recoverStaleGps() async {
    final last = _lastSuccessfulGpsAt;
    if (_sending ||
        (last != null &&
            DateTime.now().difference(last) <= const Duration(seconds: 90))) {
      return;
    }
    final recovered = await recoverNow();
    if (recovered || _technicianId == null) return;
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(_publishPosition, onError: (_) {});
  }

  Future<void> _publishPosition(Position position) async {
    if (_sending || !isWithinTechnicianTrackingDay(DateTime.now())) {
      return;
    }
    final technicianId = _technicianId;
    if (technicianId == null) return;
    _sending = true;
    try {
      if (isTechnicianOvertime(position.timestamp)) {
        _activeOvertimeDateKey = overtimeDayKey(position.timestamp);
      }
      await _repository.updateLocation(
        TechnicianLocation(
          technicianId: technicianId,
          latitude: position.latitude,
          longitude: position.longitude,
          updatedAt: position.timestamp,
          activeBookingId: _activeBookingId,
          heading: position.heading.isNaN ? null : position.heading,
          bearing: position.heading.isNaN ? null : position.heading,
          speed: position.speed.isNaN ? null : position.speed,
          accuracy: position.accuracy.isNaN ? null : position.accuracy,
          isOnline: true,
          branchId: _branchId,
        ),
      );
      _lastSuccessfulGpsAt = DateTime.now();
    } finally {
      _sending = false;
    }
  }

  LocationSettings _locationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FixNow working-hours tracking',
            notificationText:
                'Tracking is active. Work after 10:00 PM is recorded as overtime.',
            enableWakeLock: true,
          ),
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        ),
      _ => const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
    };
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
