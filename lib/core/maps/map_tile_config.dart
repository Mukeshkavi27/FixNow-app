import 'package:flutter/foundation.dart';

/// Production builds should provide an OSM-compatible tile endpoint with:
/// --dart-define=FIXNOW_MAP_TILE_URL=https://provider/{z}/{x}/{y}.png
const _configuredMapTileUrl = String.fromEnvironment(
  'FIXNOW_MAP_TILE_URL',
);

String get fixNowMapTileUrl => _configuredMapTileUrl.trim().isEmpty
    ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
    : _configuredMapTileUrl.trim();

const _configuredMapTileUserAgent = String.fromEnvironment(
  'FIXNOW_MAP_TILE_USER_AGENT',
);

String get fixNowMapTileUserAgent => _configuredMapTileUserAgent.trim().isEmpty
    ? 'live.fixnow.app'
    : _configuredMapTileUserAgent.trim();

bool get isUsingCommunityOpenStreetMapTiles =>
    fixNowMapTileUrl.contains('tile.openstreetmap.org');

void warnIfCommunityTilesAreUsedInRelease() {
  if (kReleaseMode && isUsingCommunityOpenStreetMapTiles) {
    debugPrint(
      'FIXNOW_MAP_TILE_URL is using the community OpenStreetMap service. '
      'Configure a production tile provider before a large rollout.',
    );
  }
}
