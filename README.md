# Diaspora Nearby

Diaspora Nearby is a Flutter and Firebase app for helping diaspora communities connect with nearby compatriots, local communities, events, organizations, and trust-based services.

## Core Features

- Nearby Connect: discover and message compatriots near your current location.
- Community Hubs: participate in city, state, country, and continent communities.
- Events and Organizations: discover diaspora-led events and organizations.
- Background Notifications: receive nearby-community notifications.
- Global Search: search communities and users across supported regions.
- DSP Economy: earn Diaspora Social Points through P.o.S.A activity and P.o.C.T trust signals.
- National Pride: contribute to country-level leaderboards and treasury mechanics.

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
- Put `GoogleService-Info.plist` in `ios/Runner/` locally.
- Keep local `.env` files out of git.
- Document new environment variables in the matching `.env.example`.

### Run

```bash
flutter run
```

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
