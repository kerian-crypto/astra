/// Configuration injectée à la compilation :
/// `flutter run --dart-define=API_BASE_URL=https://api.astra.example/api/v1`
abstract final class AppConfig {
  /// Par défaut : l'API locale vue depuis l'émulateur Android.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);
}
