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
  final end = DateTime(time.year, time.month, time.day + 1);
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
