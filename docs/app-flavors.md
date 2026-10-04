# App Flavors

Diaspora Nearby has three installable app environments.

| Environment | Launcher name | Android app ID | iOS bundle ID | Dart entrypoint |
| --- | --- | --- | --- | --- |
| Dev | Diaspora Nearby Dev | `com.diasporanearby.diasporanearby.dev` | `com.diasporanearby.diasporaFlutter.dev` | `lib/main_dev.dart` |
| Staging | Diaspora Nearby Staging | `com.diasporanearby.diasporanearby.staging` | `com.diasporanearby.diasporaFlutter.staging` | `lib/main_staging.dart` |
| Production | Diaspora Nearby | `com.diasporanearby.diasporanearby` | `com.diasporanearby.diasporaFlutter` | `lib/main_production.dart` |

Dev and staging builds show an in-app environment ribbon. Production does not.

## Run On A Device

```bash
flutter run --flavor dev -t lib/main_dev.dart --dart-define=APP_ENV=dev
flutter run --flavor staging -t lib/main_staging.dart --dart-define=APP_ENV=staging
flutter run --flavor production -t lib/main_production.dart --dart-define=APP_ENV=production
```

## Release Builds

```bash
flutter build apk --flavor production -t lib/main_production.dart --release --dart-define=APP_ENV=production
flutter build appbundle --flavor production -t lib/main_production.dart --release --dart-define=APP_ENV=production
flutter build ios --flavor production -t lib/main_production.dart --release --dart-define=APP_ENV=production
```

## Firebase

Production uses the checked-in public Firebase client options. Dev and staging
now fail closed unless a different Firebase project is injected with these
build-time definitions:

```text
FIREBASE_API_KEY
FIREBASE_APP_ID
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_PROJECT_ID
FIREBASE_STORAGE_BUCKET
FIREBASE_DATABASE_URL
FIREBASE_AUTH_DOMAIN
FIREBASE_MEASUREMENT_ID
```

Create separate Firebase projects for dev and staging and also place their
platform config files at:

```text
android/app/src/dev/google-services.json
android/app/src/staging/google-services.json
android/app/src/production/google-services.json
ios/Runner/GoogleService-Info-Dev.plist
ios/Runner/GoogleService-Info-Staging.plist
ios/Runner/GoogleService-Info-Production.plist
```

The Firebase config files are ignored by git, so they must be managed through
the secure secrets/configuration process rather than committed directly.
The runtime rejects a dev/staging build whose injected project ID equals the
production project ID.

Google Maps/Places credentials must also be injected at build time. Use
`--dart-define=GOOGLE_MAPS_API_KEY=...` for Dart REST/static-map callers,
`MAPS_API_KEY` in Android `local.properties`/CI secrets, and the
`GOOGLE_MAPS_API_KEY` Xcode build setting for iOS. Restrict each Google Cloud
key to its platform, application identifier, and required APIs; the repository
does not contain a fallback Maps key.
