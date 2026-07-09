import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../app/theme/app_theme.dart';
import 'google_maps_config.dart';

class GoogleMapPoint {
  const GoogleMapPoint({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.color,
    this.icon,
    this.bearing,
  });

  final double latitude;
  final double longitude;
  final String label;
  final Color color;
  final IconData? icon;
  final double? bearing;
}

class GoogleStaticMap extends StatelessWidget {
  const GoogleStaticMap({
    required this.points,
    required this.fallback,
    this.zoom = 13,
    this.polylinePoints = const [],
    super.key,
  });

  final List<GoogleMapPoint> points;
  final List<GoogleMapPoint> polylinePoints;
  final int zoom;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (!GoogleMapsConfig.isConfigured || points.isEmpty) return fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          _staticMapUri().toString(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const ColoredBox(
              color: AppTheme.surface,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                'Google Maps',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Uri _staticMapUri() {
    final params = <String, String>{
      'size': '900x420',
      'scale': '2',
      'maptype': 'roadmap',
      'key': GoogleMapsConfig.apiKey,
    };
    if (points.length == 1) {
      params['center'] = '${points.first.latitude},${points.first.longitude}';
      params['zoom'] = zoom.toString();
    }
    if (polylinePoints.length >= 2) {
      params['path'] = [
        'color:0x0B5EEAff',
        'weight:5',
        ...polylinePoints.map((point) => '${point.latitude},${point.longitude}'),
      ].join('|');
    }

    final markers = <String>[
      for (final point in points)
        [
          'color:${_markerColor(point.color)}',
          'label:${point.label.substring(0, 1).toUpperCase()}',
          '${point.latitude},${point.longitude}',
        ].join('|'),
    ];

    return Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      ...params,
      'markers': markers,
    });
  }

  String _markerColor(Color color) {
    if (color == AppTheme.accent) return 'orange';
    if (color == AppTheme.primary) return 'blue';
    return 'red';
  }
}

class OpenStreetMapFallback extends StatelessWidget {
  const OpenStreetMapFallback({
    required this.points,
    this.zoom = 13,
    this.polylinePoints = const [],
    super.key,
  });

  final List<GoogleMapPoint> points;
  final List<GoogleMapPoint> polylinePoints;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final center = points.isEmpty
        ? const LatLng(20.5937, 78.9629)
        : LatLng(points.first.latitude, points.first.longitude);
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: points.isEmpty ? 4 : zoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.fixnow.app',
        ),
        if (polylinePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  for (final point in polylinePoints)
                    LatLng(point.latitude, point.longitude),
                ],
                color: AppTheme.primary,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final point in points)
              Marker(
                point: LatLng(point.latitude, point.longitude),
                width: 52,
                height: 52,
                child: _MapMarker(point: point),
              ),
          ],
        ),
      ],
    );
  }
}

class InAppLiveMap extends StatelessWidget {
  const InAppLiveMap({
    required this.points,
    this.zoom = 13,
    this.routePolyline = const [],
    this.badge = 'Live in-app tracking',
    super.key,
  });

  final List<GoogleMapPoint> points;
  final List<LatLng> routePolyline;
  final double zoom;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final camera = _cameraFor(constraints);
        return Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              key: ValueKey(
                '${camera.center.latitude.toStringAsFixed(5)},'
                '${camera.center.longitude.toStringAsFixed(5)},'
                '${camera.zoom.toStringAsFixed(2)},'
                '${routePolyline.length}',
              ),
              options: MapOptions(
                initialCenter: camera.center,
                initialZoom: camera.zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fixnow.app',
                ),
                if (routePolyline.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePolyline,
                        color: AppTheme.primary,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (final point in points)
                      Marker(
                        point: LatLng(point.latitude, point.longitude),
                        width: 54,
                        height: 54,
                        child: _MapMarker(point: point),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  _MapCamera _cameraFor(BoxConstraints constraints) {
    final cameraPoints = [
      if (routePolyline.length >= 2) ...routePolyline,
      if (routePolyline.length < 2)
        for (final point in points) LatLng(point.latitude, point.longitude),
    ];
    if (cameraPoints.isEmpty) {
      return const _MapCamera(center: LatLng(20.5937, 78.9629), zoom: 4);
    }
    final center = _centerOfLatLng(cameraPoints);
    if (cameraPoints.length == 1) {
      return _MapCamera(center: center, zoom: zoom);
    }
    final mapWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 360.0;
    final mapHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 220.0;
    final boundsZoom = _zoomForBounds(
      points: cameraPoints,
      width: math.max(120, mapWidth - 64),
      height: math.max(120, mapHeight - 64),
    );
    return _MapCamera(center: center, zoom: math.min(zoom, boundsZoom));
  }

  LatLng _centerOfLatLng(List<LatLng> points) {
    final latitude = points.fold<double>(0, (sum, point) => sum + point.latitude) /
        points.length;
    final longitude =
        points.fold<double>(0, (sum, point) => sum + point.longitude) /
            points.length;
    return LatLng(latitude, longitude);
  }
}

class _MapCamera {
  const _MapCamera({
    required this.center,
    required this.zoom,
  });

  final LatLng center;
  final double zoom;
}

double _zoomForBounds({
  required List<LatLng> points,
  required double width,
  required double height,
}) {
  var minLatitude = points.first.latitude;
  var maxLatitude = points.first.latitude;
  var minLongitude = points.first.longitude;
  var maxLongitude = points.first.longitude;

  for (final point in points.skip(1)) {
    minLatitude = math.min(minLatitude, point.latitude);
    maxLatitude = math.max(maxLatitude, point.latitude);
    minLongitude = math.min(minLongitude, point.longitude);
    maxLongitude = math.max(maxLongitude, point.longitude);
  }

  final latitudeFraction =
      (_mercatorLatitude(maxLatitude) - _mercatorLatitude(minLatitude)).abs() /
          math.pi;
  final longitudeDelta = (maxLongitude - minLongitude).abs();
  final longitudeFraction = longitudeDelta / 360;
  final latitudeZoom = _zoomForFraction(latitudeFraction, height);
  final longitudeZoom = _zoomForFraction(longitudeFraction, width);
  return math.min(latitudeZoom, longitudeZoom).clamp(3, 17).toDouble();
}

double _zoomForFraction(double fraction, double mapPixels) {
  if (fraction <= 0) return 17;
  return math.log(mapPixels / 256 / fraction) / math.ln2;
}

double _mercatorLatitude(double latitude) {
  final radians = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return math.log(math.tan(radians / 2 + math.pi / 4));
}

class RoadRouteMap extends StatefulWidget {
  const RoadRouteMap({
    required this.points,
    required this.origin,
    required this.destination,
    this.zoom = 13,
    this.badge = 'Live route',
    this.noOriginLabel = 'Waiting for technician GPS',
    this.showRouteSummary = true,
    this.showRouteLine = true,
    this.onRouteUpdated,
    super.key,
  });

  final List<GoogleMapPoint> points;
  final GoogleMapPoint? origin;
  final GoogleMapPoint destination;
  final double zoom;
  final String badge;
  final String noOriginLabel;
  final bool showRouteSummary;
  final bool showRouteLine;
  final ValueChanged<RoadRouteSummary?>? onRouteUpdated;

  @override
  State<RoadRouteMap> createState() => _RoadRouteMapState();
}

class RoadRouteSummary {
  const RoadRouteSummary({
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final double distanceMeters;
  final double durationSeconds;

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get durationLabel {
    final minutes = (durationSeconds / 60).round().clamp(1, 999);
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
  }
}

class _RoadRouteData {
  const _RoadRouteData({
    required this.polyline,
    required this.summary,
  });

  final List<LatLng> polyline;
  final RoadRouteSummary summary;
}

class _RoadRouteMapState extends State<RoadRouteMap> {
  Future<_RoadRouteData?>? _routeFuture;
  String? _routeKey;

  @override
  void initState() {
    super.initState();
    _refreshRoute();
  }

  @override
  void didUpdateWidget(covariant RoadRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshRoute();
  }

  void _refreshRoute() {
    final origin = widget.origin;
    final key = origin == null || !widget.showRouteLine
        ? null
        : '${origin.latitude.toStringAsFixed(5)},'
            '${origin.longitude.toStringAsFixed(5)}-'
            '${widget.destination.latitude.toStringAsFixed(5)},'
            '${widget.destination.longitude.toStringAsFixed(5)}';
    if (key == _routeKey) return;
    _routeKey = key;
    _routeFuture = origin == null || !widget.showRouteLine
        ? Future.value(null)
        : _fetchRoute(origin);
  }

  Future<_RoadRouteData?> _fetchRoute(GoogleMapPoint origin) async {
    final route = GoogleMapsConfig.isConfigured
        ? await _fetchGoogleRoute(origin)
        : GoogleMapsConfig.isOpenRouteServiceConfigured
            ? await _fetchOpenRouteServiceRoute(origin)
            : await _fetchOsrmRoute(origin);
    if (mounted) widget.onRouteUpdated?.call(route?.summary);
    return route;
  }

  Future<_RoadRouteData?> _fetchGoogleRoute(GoogleMapPoint origin) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination':
          '${widget.destination.latitude},${widget.destination.longitude}',
      'mode': 'driving',
      'key': GoogleMapsConfig.apiKey,
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _fetchSecondaryRoute(origin);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return _fetchSecondaryRoute(origin);
      final routes = data['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return _fetchSecondaryRoute(origin);
      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>? ?? const [];
      if (legs.isEmpty) return _fetchSecondaryRoute(origin);
      final leg = legs.first as Map<String, dynamic>;
      final encoded =
          ((route['overview_polyline'] as Map<String, dynamic>?)?['points'])
              as String?;
      if (encoded == null || encoded.isEmpty) {
        return _fetchSecondaryRoute(origin);
      }
      return _RoadRouteData(
        polyline: _decodeGooglePolyline(encoded),
        summary: RoadRouteSummary(
          distanceMeters:
              ((leg['distance'] as Map<String, dynamic>?)?['value'] as num?)
                      ?.toDouble() ??
                  0,
          durationSeconds:
              ((leg['duration'] as Map<String, dynamic>?)?['value'] as num?)
                      ?.toDouble() ??
                  0,
        ),
      );
    } catch (_) {
      return _fetchSecondaryRoute(origin);
    }
  }

  Future<_RoadRouteData?> _fetchSecondaryRoute(GoogleMapPoint origin) {
    return GoogleMapsConfig.isOpenRouteServiceConfigured
        ? _fetchOpenRouteServiceRoute(origin)
        : _fetchOsrmRoute(origin);
  }

  Future<_RoadRouteData?> _fetchOpenRouteServiceRoute(
    GoogleMapPoint origin,
  ) async {
    final uri = Uri.https(
      'api.openrouteservice.org',
      '/v2/directions/driving-car',
      {
        'api_key': GoogleMapsConfig.openRouteServiceApiKey,
        'start': '${origin.longitude},${origin.latitude}',
        'end': '${widget.destination.longitude},${widget.destination.latitude}',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _fetchOsrmRoute(origin);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) return _fetchOsrmRoute(origin);
      final feature = features.first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? const {};
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? const [];
      final properties =
          feature['properties'] as Map<String, dynamic>? ?? const {};
      final segments = properties['segments'] as List<dynamic>? ?? const [];
      final segment = segments.isEmpty
          ? const <String, dynamic>{}
          : segments.first as Map<String, dynamic>;
      if (coordinates.length < 2) return _fetchOsrmRoute(origin);
      return _RoadRouteData(
        polyline: coordinates
            .whereType<List<dynamic>>()
            .where((coord) => coord.length >= 2)
            .map(
              (coord) => LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ),
            )
            .toList(),
        summary: RoadRouteSummary(
          distanceMeters: (segment['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (segment['duration'] as num?)?.toDouble() ?? 0,
        ),
      );
    } catch (_) {
      return _fetchOsrmRoute(origin);
    }
  }

  Future<_RoadRouteData?> _fetchOsrmRoute(GoogleMapPoint origin) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${widget.destination.longitude},${widget.destination.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>? ?? const {};
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? const [];
      if (coordinates.length < 2) return null;
      return _RoadRouteData(
        polyline: coordinates
            .whereType<List<dynamic>>()
            .where((coord) => coord.length >= 2)
            .map(
              (coord) => LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ),
            )
            .toList(),
        summary: RoadRouteSummary(
          distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final origin = widget.origin;
    return FutureBuilder<_RoadRouteData?>(
      future: _routeFuture,
      builder: (context, snapshot) {
        final route = snapshot.data;
        final statusText = !widget.showRouteLine
            ? null
            : origin == null
                ? widget.noOriginLabel
                : snapshot.connectionState == ConnectionState.waiting
                    ? 'Finding road route...'
                    : route == null
                        ? 'Road route unavailable'
                        : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            InAppLiveMap(
              points: widget.points,
              routePolyline:
                  widget.showRouteLine ? route?.polyline ?? const [] : const [],
              zoom: widget.zoom,
              badge: widget.badge,
            ),
            if (route != null && widget.showRouteLine && widget.showRouteSummary)
              Positioned(
                left: 10,
                bottom: 10,
                child: _RouteSummaryBadge(summary: route.summary),
              ),
            if (statusText != null)
              Positioned(
                left: 10,
                bottom: 10,
                child: _RouteStatusBadge(text: statusText),
              ),
          ],
        );
      },
    );
  }
}

class _RouteStatusBadge extends StatelessWidget {
  const _RouteStatusBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delivery_dining_outlined,
              color: AppTheme.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSummaryBadge extends StatelessWidget {
  const _RouteSummaryBadge({
    required this.summary,
    this.approximate = false,
  });

  final RoadRouteSummary summary;
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              '${approximate ? 'Approx ETA' : 'ETA'} '
              '${summary.durationLabel} - ${summary.distanceLabel}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<LatLng> _decodeGooglePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

    points.add(LatLng(latitude / 1E5, longitude / 1E5));
  }

  return points;
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.point});

  final GoogleMapPoint point;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: point.color, width: 3),
        boxShadow: [
          BoxShadow(
            color: point.color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: point.icon == null
          ? Text(
              point.label.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: point.color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            )
          : Transform.rotate(
              angle: (point.bearing ?? 0) * math.pi / 180,
              child: Icon(point.icon, color: point.color, size: 22),
            ),
    );
  }
}
