class GoogleMapsConfig {
  const GoogleMapsConfig._();

  static const apiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const openRouteServiceApiKey =
      String.fromEnvironment('OPEN_ROUTE_SERVICE_API_KEY');

  static bool get isConfigured => apiKey.trim().isNotEmpty;
  static bool get isOpenRouteServiceConfigured =>
      openRouteServiceApiKey.trim().isNotEmpty;
}
