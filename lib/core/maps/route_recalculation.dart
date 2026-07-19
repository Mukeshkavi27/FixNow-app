import 'dart:math' as math;

const defaultRouteRecalculationDistanceMeters = 100.0;
const defaultRouteRecalculationInterval = Duration(seconds: 60);
const technicianGpsStaleThreshold = Duration(seconds: 90);

bool isGpsUpdateStale(
  DateTime updatedAt, {
  DateTime? now,
  Duration threshold = technicianGpsStaleThreshold,
}) {
  final elapsed = (now ?? DateTime.now()).difference(updatedAt);
  return elapsed > threshold;
}

bool shouldRecalculateRoadRoute({
  required double previousLatitude,
  required double previousLongitude,
  required double latitude,
  required double longitude,
  required DateTime calculatedAt,
  DateTime? now,
  double distanceThresholdMeters = defaultRouteRecalculationDistanceMeters,
  Duration interval = defaultRouteRecalculationInterval,
}) {
  final currentTime = now ?? DateTime.now();
  if (currentTime.difference(calculatedAt) >= interval) return true;
  return navigationDistanceMeters(
        previousLatitude,
        previousLongitude,
        latitude,
        longitude,
      ) >=
      distanceThresholdMeters;
}

double navigationDistanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const radius = 6371000.0;
  final lat1 = latitudeA * math.pi / 180;
  final lat2 = latitudeB * math.pi / 180;
  final deltaLat = (latitudeB - latitudeA) * math.pi / 180;
  final deltaLng = (longitudeB - longitudeA) * math.pi / 180;
  final value = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
}
