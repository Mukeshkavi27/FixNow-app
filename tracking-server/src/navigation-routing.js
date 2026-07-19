export function canReuseNavigationRoute(
  existing,
  update,
  {
    cacheMeters = 120,
    deviationMeters = 90,
  } = {},
) {
  if (!existing?.route?.points?.length) return false;
  const originMove = navigationMetersBetween(existing.origin, {
    lat: update.latitude,
    lng: update.longitude,
  });
  const destinationMove = navigationMetersBetween(existing.destination, {
    lat: update.destinationLatitude,
    lng: update.destinationLongitude,
  });
  if (originMove > cacheMeters || destinationMove > cacheMeters) return false;
  return minDistanceToNavigationPolyline(
    { lat: update.latitude, lng: update.longitude },
    existing.route.points,
  ) <= deviationMeters;
}

export function minDistanceToNavigationPolyline(point, polyline) {
  if (!polyline?.length) return Infinity;
  return Math.min(
    ...polyline.map((item) => navigationMetersBetween(point, item)),
  );
}

export function navigationMetersBetween(a, b) {
  const earthRadius = 6371000;
  const lat1 = toRadians(a.lat);
  const lat2 = toRadians(b.lat);
  const deltaLat = toRadians(b.lat - a.lat);
  const deltaLng = toRadians(b.lng - a.lng);
  const value = Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

export async function safeNavigationRoute(fetchRoute, onError = () => {}) {
  try {
    return await fetchRoute();
  } catch (error) {
    onError(error);
    return null;
  }
}

function toRadians(value) {
  return value * Math.PI / 180;
}
