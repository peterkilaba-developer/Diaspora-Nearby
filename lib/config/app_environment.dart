import 'package:flutter/foundation.dart';

enum AppEnvironment {
  dev,
  staging,
  production;

  static AppEnvironment fromName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }
}

class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  static const String _envName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static AppEnvironment _current = AppEnvironment.fromName(_envName);

  static AppEnvironment get current => _current;

  static void configure(AppEnvironment environment) {
    _current = environment;
  }

  static bool get isProduction => current == AppEnvironment.production;

  static String get name => current.name;

  static String get appTitle {
    switch (current) {
      case AppEnvironment.dev:
        return 'Diaspora Nearby Dev';
      case AppEnvironment.staging:
        return 'Diaspora Nearby Staging';
      case AppEnvironment.production:
        return 'Diaspora Nearby';
    }
  }

  static String get bannerLabel {
    switch (current) {
      case AppEnvironment.dev:
        return 'DEV';
      case AppEnvironment.staging:
        return 'STAGING';
      case AppEnvironment.production:
        return '';
    }
  }

  static void logStartup() {
    debugPrint('App environment: $name');
  }
}
