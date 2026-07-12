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
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

## Release Builds

```bash
flutter build apk --flavor production -t lib/main_production.dart --release
flutter build appbundle --flavor production -t lib/main_production.dart --release
flutter build ios --flavor production -t lib/main_production.dart --release
```

## Firebase

The Dart Firebase options currently point all environments at the existing
Firebase project, `diaspora-nearby-a3dac`.

For fully isolated enterprise environments, create separate Firebase apps or
projects for dev and staging, then place their platform config files at:

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
