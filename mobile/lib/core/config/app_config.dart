class AppConfig {
  const AppConfig._();

  static const String appName = 'EduForge AI';

  /// Override at build/run time with:
  /// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const int maxUploadBytes = 25 * 1024 * 1024; // 25 MB
  static const List<String> allowedUploadExtensions = ['pdf', 'docx', 'pptx'];
}
