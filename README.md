# Diaspora Nearby

Diaspora Nearby is a Flutter and Firebase application built for anyone positioned between their home country and a host country—whether temporarily (corporate expats, international diplomats, business professionals, international travelers, exchange students, temporary workers) or permanently (naturalized citizens, permanent residents, settled diaspora). It empowers anyone with a temporary or permanent dual geographic identity to connect with nearby compatriots, local communities, events, organizations, and trust-based services.

## Core Features

- **Target User Positioning**: Designed for individuals with dual geographic identity (living between Home Country and Host Country either temporarily or permanently).
- **Nearby Connect**: Discover and message compatriots near your current location.
- **Nested Hierarchical Community Hubs**: Navigate and participate in nested geographic communities (Global → Continent → Country → State/Province → City/Town).
- **Events and Organizations**: Discover diaspora-led events and organizations.
- **Background Notifications**: Receive nearby-community notifications.
- **Global Search**: Search communities and users across supported regions.
- **DSP Economy**: Earn Diaspora Social Points through Proof of Activity (P.O.A) and Proof of Community Trust (PCT) trust signals.
- **National Pride**: Contribute to country-level leaderboards and treasury mechanics.

## Technical Stack

- Flutter and Dart
- Riverpod
- Firebase Auth, Firestore, Realtime Database, Cloud Functions, Cloud Storage
- GoRouter
- Hardhat and Solidity for blockchain contracts

## Getting Started

### Prerequisites

- Flutter SDK `3.41.4` for parity with CI until the icon dependency migration is complete.
- Node.js `22` for Firebase Functions, Firestore rule tests, and blockchain CI parity.
- A Firebase project with Auth, Firestore, Realtime Database, Storage, and Cloud Functions configured.

### Install

```bash
git clone https://github.com/peterkilaba-developer/Diaspora-Nearby.git
cd Diaspora-Nearby
flutter pub get
```

Install package-specific dependencies when working in those areas:

```bash
cd functions && npm ci
cd ../firestore-rules-test && npm ci
cd ../blockchain && npm ci
```

### Firebase Configuration

Do not commit local Firebase config or service-account material.

- Put `google-services.json` in `android/app/` locally.
- For Android flavors, put environment-specific copies in `android/app/src/dev/`,
  `android/app/src/staging/`, and `android/app/src/production/`.
- Put `GoogleService-Info.plist` in `ios/Runner/` locally.
- Keep local `.env` files out of git.
- Document new environment variables in the matching `.env.example`.

### Run

```bash
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

See [docs/app-flavors.md](docs/app-flavors.md) for package IDs, bundle IDs, and release commands.

## Validation

Run the checks that match the area you changed:

```bash
dart format --set-exit-if-changed lib test integration_test scripts
flutter analyze
flutter test
node scripts/check-repo-hygiene.js
```

```bash
cd functions && npm run lint && npm audit --omit=dev --audit-level=high
cd firestore-rules-test && npm test
cd blockchain && npm run compile && npm test && npm audit --omit=dev --audit-level=high
```

## Branching and Releases

The repository uses staged promotion:

- `feature/*` and `bugfix/*` target `dev`.
- `dev` promotes to `staging` after CI and release-scope approval.
- `staging` promotes to `production` after acceptance testing.
- `hotfix/*` targets `staging` or `production`, then back-merges into `dev`.

See [docs/branching-strategy.md](docs/branching-strategy.md) and [docs/enterprise-readiness.md](docs/enterprise-readiness.md).

## Security

See [SECURITY.md](SECURITY.md). Never commit secrets, signing files, generated caches, package directories, or local diagnostic dumps.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
