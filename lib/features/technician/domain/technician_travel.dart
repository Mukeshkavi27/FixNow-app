import 'dart:math' as math;

import 'technician_location.dart';

const technicianTrackingStartHour = 9;
const technicianTrackingStartMinute = 20;
const technicianTrackingEndHour = 22;

DateTime technicianTrackingStart(DateTime day) => DateTime(
      day.year,
      day.month,
      day.day,
      technicianTrackingStartHour,
      technicianTrackingStartMinute,
    );

DateTime technicianTrackingEnd(DateTime day) => DateTime(
      day.year,
      day.month,
      day.day,
      technicianTrackingEndHour,
    );

bool isWithinTechnicianTrackingWindow(DateTime time) {
  final start = technicianTrackingStart(time);
  final end = technicianTrackingEnd(time);
  return !time.isBefore(start) && time.isBefore(end);
}

bool isWithinTechnicianTrackingDay(DateTime time) {
  final start = technicianTrackingStart(time);
  final end = technicianTrackingEnd(time);
  return !time.isBefore(start) && time.isBefore(end);
}

double technicianTravelDistanceMeters(List<TechnicianLocation> points) {
  if (points.length < 2) return 0;
  var distance = 0.0;
  for (var index = 1; index < points.length; index++) {
    distance += _metersBetween(points[index - 1], points[index]);
  }
  return distance;
}

List<TechnicianLocation> technicianVisitedLocations(
  List<TechnicianLocation> points, {
  double minimumDistanceMeters = 200,
}) {
  if (points.isEmpty) return const [];
  final visited = <TechnicianLocation>[points.first];
  for (final point in points.skip(1)) {
    if (_metersBetween(visited.last, point) >= minimumDistanceMeters) {
      visited.add(point);
    }
  }
  if (visited.last != points.last) visited.add(points.last);
  return visited;
}

class TechnicianIdlePeriod {
  const TechnicianIdlePeriod({
    required this.startedAt,
    required this.endedAt,
    required this.latitude,
    required this.longitude,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final double latitude;
  final double longitude;

  Duration get duration => endedAt.difference(startedAt);
}

/// Finds stationary periods in the minute-by-minute workday history.
List<TechnicianIdlePeriod> technicianIdlePeriods(
  List<TechnicianLocation> points, {
  double stationaryRadiusMeters = 35,
  Duration minimumDuration = const Duration(minutes: 5),
}) {
  if (points.length < 2) return const [];
  final sorted = [...points]
    ..sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
  final periods = <TechnicianIdlePeriod>[];
  var anchor = sorted.first;
  var last = sorted.first;
  for (final point in sorted.skip(1)) {
    if (_metersBetween(anchor, point) <= stationaryRadiusMeters) {
      last = point;
      continue;
    }
    if (last.updatedAt.difference(anchor.updatedAt) >= minimumDuration) {
      periods.add(TechnicianIdlePeriod(
        startedAt: anchor.updatedAt,
        endedAt: last.updatedAt,
        latitude: anchor.latitude,
        longitude: anchor.longitude,
      ));
    }
    anchor = point;
    last = point;
  }
  if (last.updatedAt.difference(anchor.updatedAt) >= minimumDuration) {
    periods.add(TechnicianIdlePeriod(
      startedAt: anchor.updatedAt,
      endedAt: last.updatedAt,
      latitude: anchor.latitude,
      longitude: anchor.longitude,
    ));
  }
  return periods;
}

double _metersBetween(
  TechnicianLocation left,
  TechnicianLocation right,
) {
  const radius = 6371000.0;
  final lat1 = left.latitude * math.pi / 180;
  final lat2 = right.latitude * math.pi / 180;
  final deltaLat = (right.latitude - left.latitude) * math.pi / 180;
  final deltaLng = (right.longitude - left.longitude) * math.pi / 180;
  final value = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
}
