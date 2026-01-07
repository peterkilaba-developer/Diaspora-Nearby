# Diaspora Nearby

**Diaspora Nearby** is a social network designed to help members of diaspora communities connect with each other, find local events, and discover organizations in their current host location.

## 🚀 Features

- **Nearby Connect**: Find and message compatriates living near you.
- **Community Hubs**: Join location-based communities (City, State, Country, Continent).
- **Events & Organizations**: Discover and participate in diaspora-led events and organizations.
- **Background Notifications**: Get notified when someone from your home country is nearby.
- **Global Search**: Search for communities and users across the globe.

## 🛠️ Technical Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **State Management**: [Riverpod](https://riverpod.dev)
- **Database**: [Firebase Cloud Firestore](https://firebase.google.com/docs/firestore) & [Realtime Database](https://firebase.google.com/docs/database)
- **Authentication**: [Firebase Auth](https://firebase.google.com/docs/auth)
- **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
- **Backend Services**: Firebase Cloud Functions, Cloud Storage

## 📦 Getting Started

### Prerequisites
- Flutter SDK (latest stable version)
- Dart SDK
- A Firebase project with Firestore, Realtime Database, and Auth enabled.

### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/peterkilaba-developer/Diaspora-Nearby.git
    cd Diaspora-Nearby
    ```

2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase**:
    - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) from your Firebase Console.
    - Place `google-services.json` in `android/app/`.
    - Place `GoogleService-Info.plist` in `ios/Runner/`.

4.  **Run the app**:
    ```bash
    flutter run
    ```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
