import 'dart:math' as math;

import 'branch_info.dart';

class BranchResolution {
  const BranchResolution({
    required this.branch,
    required this.reason,
  });

  final BranchInfo branch;
  final String reason;
}

class BranchResolver {
  static BranchResolution resolve({
    required List<BranchInfo> branches,
    String? address,
    double? latitude,
    double? longitude,
  }) {
    if (branches.isEmpty) {
      throw StateError('No branches are configured.');
    }
    final matched = matchByAddress(branches, address);
    if (matched != null) {
      return BranchResolution(
        branch: matched,
        reason: 'matched_branch_by_address',
      );
    }

    if (latitude != null && longitude != null) {
      final nearest = nearestByCoordinates(branches, latitude, longitude);
      return BranchResolution(
        branch: nearest,
        reason: 'nearest_branch_by_location',
      );
    }

    return BranchResolution(
      branch: branches.first,
      reason: 'default_branch_fallback',
    );
  }

  static BranchInfo nearestByCoordinates(
    List<BranchInfo> branches,
    double latitude,
    double longitude,
  ) {
    final coordinateBranches =
        branches.where((branch) => branch.hasCoordinates).toList();
    if (coordinateBranches.isEmpty) {
      return branches.first;
    }
    BranchInfo nearest = coordinateBranches.first;
    var shortest = double.infinity;
    for (final branch in coordinateBranches) {
      final distance = _distanceMeters(
        latitude,
        longitude,
        branch.latitude,
        branch.longitude,
      );
      if (distance < shortest) {
        shortest = distance;
        nearest = branch;
      }
    }
    return nearest;
  }

  static BranchInfo? matchByAddress(
      List<BranchInfo> branches, String? address) {
    final normalized = address?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return null;

    for (final branch in branches) {
      if (normalized.contains(branch.city.toLowerCase()) ||
          normalized.contains(branch.name.toLowerCase()) ||
          branch.aliases
              .any((alias) => normalized.contains(alias.toLowerCase()))) {
        return branch;
      }
    }
    return null;
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
