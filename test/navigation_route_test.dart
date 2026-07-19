import 'package:fixnow/core/maps/google_static_map.dart';
import 'package:fixnow/core/maps/route_recalculation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale GPS is detected after 90 seconds', () {
    final now = DateTime(2026, 7, 14, 10);
    expect(
      isGpsUpdateStale(
        now.subtract(const Duration(seconds: 90)),
        now: now,
      ),
      isFalse,
    );
    expect(
      isGpsUpdateStale(
        now.subtract(const Duration(seconds: 91)),
        now: now,
      ),
      isTrue,
    );
  });

  test('route recalculation ignores GPS jitter and refreshes meaningful moves',
      () {
    final calculatedAt = DateTime(2026, 7, 14, 10);
    expect(
      shouldRecalculateRoadRoute(
        previousLatitude: 13.0827,
        previousLongitude: 80.2707,
        latitude: 13.08275,
        longitude: 80.27075,
        calculatedAt: calculatedAt,
        now: calculatedAt.add(const Duration(seconds: 20)),
      ),
      isFalse,
    );
    expect(
      shouldRecalculateRoadRoute(
        previousLatitude: 13.0827,
        previousLongitude: 80.2707,
        latitude: 13.0840,
        longitude: 80.2690,
        calculatedAt: calculatedAt,
        now: calculatedAt.add(const Duration(seconds: 20)),
      ),
      isTrue,
    );
    expect(
      shouldRecalculateRoadRoute(
        previousLatitude: 13.0827,
        previousLongitude: 80.2707,
        latitude: 13.0827,
        longitude: 80.2707,
        calculatedAt: calculatedAt,
        now: calculatedAt.add(const Duration(seconds: 60)),
      ),
      isTrue,
    );
  });

  test('ETA includes a concrete arrival time', () {
    final summary = RoadRouteSummary(
      distanceMeters: 4200,
      durationSeconds: 15 * 60,
      provider: 'google',
      calculatedAt: DateTime(2026, 7, 14, 10),
      steps: const [
        RoadRouteStep(
          instruction: 'Turn right onto Avinashi Road',
          distanceMeters: 350,
          durationSeconds: 80,
          roadName: 'Avinashi Road',
          maneuver: 'turn-right',
        ),
      ],
    );
    expect(summary.durationLabel, '15 min');
    expect(summary.distanceLabel, '4.2 km');
    expect(summary.providerLabel, 'Google Maps');
    expect(summary.steps.single.distanceLabel, '350 m');
    expect(summary.steps.single.instruction, contains('Turn right'));
    expect(
      summary.estimatedArrival(DateTime(2026, 7, 14, 10)),
      DateTime(2026, 7, 14, 10, 15),
    );
  });
}
