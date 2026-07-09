import 'package:fixnow/core/constants/app_constants.dart';
import 'package:fixnow/core/data/app_config_repository.dart';
import 'package:fixnow/core/enums/booking_status.dart';
import 'package:fixnow/core/enums/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingStatus', () {
    test('parses persisted values and keeps friendly labels', () {
      expect(
        BookingStatus.fromString('technicianAssigned'),
        BookingStatus.technicianAssigned,
      );
      expect(BookingStatus.technicianAssigned.label, 'Technician Assigned');
    });

    test('falls back safely for an unknown persisted value', () {
      expect(BookingStatus.fromString('unknown'), BookingStatus.booked);
    });
  });

  group('UserRole', () {
    test('unknown roles never gain privileged access', () {
      expect(UserRole.fromString('owner'), UserRole.customer);
    });
  });

  group('OperationsConfig', () {
    test('uses safe attendance and geofence defaults', () {
      final config = OperationsConfig.fromJson(const {});
      final day = DateTime(2026, 6, 12);

      expect(config.geofenceRadiusMeters, 250);
      expect(config.startFor(day), DateTime(2026, 6, 12));
      expect(config.endFor(day), DateTime(2026, 6, 12, 9, 30));
    });

    test('accepts remotely configured operating values', () {
      final config = OperationsConfig.fromJson(const {
        'branchLatitude': 12.5,
        'branchLongitude': 80.1,
        'geofenceRadiusMeters': 125,
        'attendanceStartHour': 9,
        'attendanceStartMinute': 20,
        'attendanceEndHour': 9,
        'attendanceEndMinute': 40,
        'whatsappApprovalNumber': '+911234567890',
      });

      expect(config.branchLatitude, 12.5);
      expect(config.geofenceRadiusMeters, 125);
      expect(config.whatsappApprovalNumber, '+911234567890');
    });
  });

  test('fallback service catalog has usable pricing labels', () {
    expect(AppConstants.applianceCategories, isNotEmpty);
    expect(
      AppConstants.applianceCategories.every(
        (category) =>
            category.name.isNotEmpty &&
            category.startingPrice.startsWith('Starting at Rs.'),
      ),
      isTrue,
    );
  });
}
