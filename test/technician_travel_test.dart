import 'package:fixnow/features/technician/domain/technician_location.dart';
import 'package:fixnow/features/technician/domain/technician_travel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TechnicianLocation point(
    double latitude,
    double longitude,
    int minute, {
    String? bookingId,
  }) {
    return TechnicianLocation(
      technicianId: 'tech-1',
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime(2026, 7, 14, 9, minute),
      activeBookingId: bookingId,
      speed: 8.5,
      accuracy: 4.2,
      branchId: 'branch-a',
    );
  }

  test('working-hours GPS window is exactly 9:20 AM until 10:00 PM', () {
    expect(isWithinTechnicianTrackingWindow(DateTime(2026, 7, 14, 9, 19)),
        isFalse);
    expect(
        isWithinTechnicianTrackingWindow(DateTime(2026, 7, 14, 9, 20)), isTrue);
    expect(isWithinTechnicianTrackingWindow(DateTime(2026, 7, 14, 21, 59)),
        isTrue);
    expect(
        isWithinTechnicianTrackingWindow(DateTime(2026, 7, 14, 22)), isFalse);
  });

  test('travel analytics calculate distance and meaningful visited points', () {
    final points = [
      point(13.08270, 80.27070, 20),
      point(13.08275, 80.27075, 21),
      point(13.08470, 80.27270, 25),
    ];

    expect(technicianTravelDistanceMeters(points), greaterThan(250));
    expect(
      technicianVisitedLocations(points, minimumDistanceMeters: 100),
      hasLength(2),
    );
  });

  test('history point retains required GPS and booking telemetry', () {
    final data = point(13.08, 80.27, 30, bookingId: 'booking-1').toJson();

    expect(data['technicianId'], 'tech-1');
    expect(data['latitude'], 13.08);
    expect(data['longitude'], 80.27);
    expect(data['speed'], 8.5);
    expect(data['accuracy'], 4.2);
    expect(data['activeBookingId'], 'booking-1');
    expect(data['updatedAt'], isNotNull);
  });
}
