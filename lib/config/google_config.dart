// lib/config/google_config.dart

class GoogleConfig {
  // Client ID per Android
  static const String androidClientId = '661566989433-uqh1hnkna2l6us8kaadnqm2t1mgra4n9.apps.googleusercontent.com';

  // Client ID per Web
  static const String webClientId = '661566989433-bnqh4qsqrib90dfime25oe4t1q1dff3a.apps.googleusercontent.com';

  // Client ID per iOS (da configurare se necessario)
  static const String iosClientId = '';

  // Scopes per Google Calendar
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
  ];
}