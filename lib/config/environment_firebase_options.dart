import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:diaspora_nearby/config/app_environment.dart';
import 'package:diaspora_nearby/firebase_options.dart';

class EnvironmentFirebaseOptions {
  EnvironmentFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (AppEnvironmentConfig.isProduction) {
      return DefaultFirebaseOptions.currentPlatform;
    }

    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    const measurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

    final required = {
      'FIREBASE_API_KEY': apiKey,
      'FIREBASE_APP_ID': appId,
      'FIREBASE_MESSAGING_SENDER_ID': senderId,
      'FIREBASE_PROJECT_ID': projectId,
      'FIREBASE_STORAGE_BUCKET': storageBucket,
    };
    final missing = required.entries
        .where((entry) => entry.value.isEmpty)
        .map((entry) => entry.key)
        .join(', ');
    if (missing.isNotEmpty) {
      throw StateError(
        '${AppEnvironmentConfig.name} Firebase is not configured. Missing: $missing',
      );
    }
    if (projectId == DefaultFirebaseOptions.web.projectId) {
      throw StateError(
        '${AppEnvironmentConfig.name} must not use the production Firebase project.',
      );
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: storageBucket,
      databaseURL: databaseUrl.isEmpty ? null : databaseUrl,
      authDomain: kIsWeb && authDomain.isNotEmpty ? authDomain : null,
      measurementId: kIsWeb && measurementId.isNotEmpty ? measurementId : null,
    );
  }
}
