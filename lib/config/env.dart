class Env {
  // Google Maps API Key for Places API and geocoding
  // Google Maps API Key from Google Cloud Console
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue:
        'AIzaSyAj0oAGYEX5osyDa_2Pn828clvv72UhEF8', // Fallback for dev only
  );
}
