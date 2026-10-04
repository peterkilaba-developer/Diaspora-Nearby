# iOS / iPhone Development Guide

This guide walks through setting up and running Diaspora Nearby on iOS (iPhone Simulator and physical iPhone devices).

---

## 1. Prerequisites (on macOS)

- **macOS Sonoma (14+)** or later
- **Xcode 15+** (with iOS 17+ / 18+ SDK)
- **CocoaPods** (`brew install cocoapods` or `sudo gem install cocoapods`)
- **Flutter SDK 3.41.4+** (`flutter doctor` should show green checkmarks for Xcode and CocoaPods)

---

## 2. Initial Setup

1. **Clone or pull the repository on your Mac:**
   ```bash
   git checkout dev
   git pull origin dev
   ```

2. **Install Flutter packages:**
   ```bash
   flutter pub get
   ```

3. **Install CocoaPods dependencies:**
   ```bash
   cd ios
   pod install
   cd ..
   ```

---

## 3. Configuration & Secrets

### Firebase
- **Production builds** use the built-in configuration from `lib/firebase_options.dart`.
- For native Firebase initialization (Push Notifications, APNs):
  - Place your Firebase iOS configuration at `ios/Runner/GoogleService-Info.plist` (see `ios/Runner/GoogleService-Info.plist.example` as a reference template).
  - For dev or staging flavors, place respectively:
    - `ios/Runner/GoogleService-Info-Dev.plist`
    - `ios/Runner/GoogleService-Info-Staging.plist`
    - `ios/Runner/GoogleService-Info-Production.plist`

### Google Maps API Key
To supply your Google Maps / Places API key for iOS:
1. Copy the secrets template:
   ```bash
   cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
   ```
2. Edit `ios/Flutter/Secrets.xcconfig`:
   ```xcconfig
   GOOGLE_MAPS_API_KEY=AIzaSy...
   ```
   *(Note: In DEBUG mode, the app will log a warning if unset instead of crashing).*

---

## 4. Running the App

### Option A: Via Command Line (Flutter CLI)

List connected devices and simulators:
```bash
flutter devices
```

**Development Flavor (Recommended for local dev):**
```bash
flutter run -d <DEVICE_ID> --flavor dev -t lib/main_dev.dart --dart-define=APP_ENV=dev
```

**Staging Flavor:**
```bash
flutter run -d <DEVICE_ID> --flavor staging -t lib/main_staging.dart --dart-define=APP_ENV=staging
```

**Production Flavor:**
```bash
flutter run -d <DEVICE_ID> --flavor production -t lib/main_production.dart --dart-define=APP_ENV=production
```

### Option B: Via Xcode (Physical iPhone or Simulator)

1. Open workspace in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Select your target scheme from the top bar:
   - `dev` (Bundle ID: `com.diasporanearby.diasporaFlutter.dev`)
   - `staging` (Bundle ID: `com.diasporanearby.diasporaFlutter.staging`)
   - `production` (Bundle ID: `com.diasporanearby.diasporaFlutter`)
3. For physical iPhone deployment:
   - Select the `Runner` project in the project navigator.
   - Go to **Signing & Capabilities**.
   - Select your Apple Developer Team and ensure automatically manage signing is enabled.
4. Select your device / simulator and click **Run** (Cmd + R).

---

## 5. Flavors and Bundle Identifiers

| Environment | Scheme | Bundle Identifier | Entrypoint |
|---|---|---|---|
| Dev | `dev` | `com.diasporanearby.diasporaFlutter.dev` | `lib/main_dev.dart` |
| Staging | `staging` | `com.diasporanearby.diasporaFlutter.staging` | `lib/main_staging.dart` |
| Production | `production` | `com.diasporanearby.diasporaFlutter` | `lib/main_production.dart` |

---

## 6. Permissions Configured

The iOS `Info.plist` and `Podfile` are pre-configured for:
- **Location**: `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription` (Nearby member discovery, event check-ins)
- **Camera**: `NSCameraUsageDescription` (QR code scanning, profile photos)
- **Microphone**: `NSMicrophoneUsageDescription` (Audio messaging)
- **Photo Library**: `NSPhotoLibraryUsageDescription` (Media upload)
- **Background Modes**: Location updates, background fetch, remote notifications
