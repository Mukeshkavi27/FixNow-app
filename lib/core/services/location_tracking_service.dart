import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/technician/data/technician_repository.dart';
import '../../features/technician/domain/technician_location.dart';
import '../../features/technician/domain/overtime_record.dart';
import '../../features/technician/domain/technician_travel.dart';

abstract interface class LocationTrackingController {
  bool get isTracking;
  String? get activeBookingId;

  Future<void> start({
    required String technicianId,
    required String bookingId,
    String? branchId,
  });

  Future<void> startWorkingDay({
    required String technicianId,
    String? branchId,
    String? bookingId,
  });

  Future<void> startShift({
    required String technicianId,
    required String branchId,
    String? bookingId,
  });

  Future<void> finishBooking();
  Future<void> stop();
  Future<bool> recoverNow();
}

final locationTrackingServiceProvider =
    Provider<LocationTrackingController>((ref) {
  final service = LocationTrackingService(
    ref.watch(technicianRepositoryProvider),
  );
  ref.onDispose(service.stop);
  return service;
});

class LocationTrackingService implements LocationTrackingController {
  LocationTrackingService(this._repository);

  final TechnicianRepository _repository;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _startTimer;
  Timer? _endTimer;
  Timer? _gpsWatchdog;
  Timer? _heartbeatTimer;
  bool _sending = false;
  String? _technicianId;
  String? _activeBookingId;
  String? _branchId;
  String? _activeOvertimeDateKey;
  DateTime? _lastSuccessfulGpsAt;
  Position? _lastPosition;
  bool _workingHoursOnly = true;

  @override
  bool get isTracking =>
      _positionSubscription != null || _startTimer?.isActive == true;
  @override
  String? get activeBookingId => _activeBookingId;

  @override
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

  @override
  Future<void> startWorkingDay({
    required String technicianId,
    String? branchId,
    String? bookingId,
  }) async {
    return _startTracking(
      technicianId: technicianId,
      branchId: branchId,
      bookingId: bookingId,
      workingHoursOnly: true,
    );
  }

  @override
  Future<void> startShift({
    required String technicianId,
    required String branchId,
    String? bookingId,
  }) {
    return _startTracking(
      technicianId: technicianId,
      branchId: branchId,
      bookingId: bookingId,
      workingHoursOnly: false,
    );
  }

  Future<void> _startTracking({
    required String technicianId,
    required String? branchId,
    required String? bookingId,
    required bool workingHoursOnly,
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
    _workingHoursOnly = workingHoursOnly;
    if (!workingHoursOnly) {
      await _beginPositionStream();
      return;
    }
    final start = technicianTrackingStart(now);
    if (now.isBefore(start)) {
      _startTimer = Timer(start.difference(now), _beginPositionStream);
    } else {
      await _beginPositionStream();
    }
    _endTimer = Timer(end.difference(now), stop);
  }

  @override
  Future<void> finishBooking() async {
    _activeBookingId = null;
    final technicianId = _technicianId;
    if (technicianId != null) {
      await _repository.clearActiveBooking(technicianId);
    }
  }

  @override
  Future<void> stop() async {
    _startTimer?.cancel();
    _startTimer = null;
    _endTimer?.cancel();
    _endTimer = null;
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    _lastPosition = null;
    _workingHoursOnly = true;
  }

  bool get _canPublishNow =>
      !_workingHoursOnly || isWithinTechnicianTrackingDay(DateTime.now());

  Future<void> _beginPositionStream() async {
    _startTimer = null;
    final technicianId = _technicianId;
    if (technicianId == null || !_canPublishNow) {
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
    // Position streams commonly pause while a device is stationary. Keep the
    // online timestamp fresh so an on-duty technician never appears offline.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) {
        final position = _lastPosition;
        if (position != null) _publishPosition(position);
      },
    );
  }

  @override
  Future<bool> recoverNow() async {
    if (_technicianId == null || !_canPublishNow) {
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
    if (_sending || !_canPublishNow) {
      return;
    }
    final technicianId = _technicianId;
    if (technicianId == null) return;
    _sending = true;
    try {
      _lastPosition = position;
      final publishedAt = DateTime.now();
      if (isTechnicianOvertime(publishedAt)) {
        _activeOvertimeDateKey = overtimeDayKey(publishedAt);
      }
      await _repository.updateLocation(
        TechnicianLocation(
          technicianId: technicianId,
          latitude: position.latitude,
          longitude: position.longitude,
          updatedAt: publishedAt,
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
            notificationTitle: 'FixNow automatic location tracking',
            notificationText:
                'Your location is shared while you are signed in.',
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
    if (kIsWeb) {
      try {
        // Calling the position API directly is required for embedded web
        // browsers that do not expose navigator.permissions.
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 20));
        return true;
      } catch (_) {
        return false;
      }
    }
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
