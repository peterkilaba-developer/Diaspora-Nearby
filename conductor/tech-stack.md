# Technology Stack

## Core Framework
*   **Framework:** Flutter (SDK 3.10.1+)
*   **Language:** Dart
*   **Architecture:** Feature-First Layered Architecture (Presentation -> Domain -> Data).

## State Management & Dependency Injection
*   **Solution:** `flutter_riverpod` (v2.0+)
*   **Pattern:** Repository Pattern with Provider-based dependency injection.
*   **Code Generation:** `freezed` and `json_serializable` for immutable data models.

## Backend & Cloud Services (Firebase)
*   **Auth:** `firebase_auth` (Phone/SMS).
*   **Database (Realtime):** `firebase_database` (RTDB) - Used for Chat Messages and Presence.
*   **Database (Document):** `cloud_firestore` - Used for Users, Communities, Events, Organizations.
*   **Database (Local):** `isar` - Used for robust local caching and offline data persistence.
*   **Storage:** `firebase_storage` - Media assets (Images, Videos, Audio, Docs).
*   **Security:** `firebase_app_check`.
*   **Notifications:** `firebase_messaging` + `flutter_local_notifications`.
*   **Monitoring:** `firebase_performance` + `firebase_crashlytics`.
*   **Logic:** `firebase_cloud_functions` - Triggers for economy and automated penalties.

## Navigation
*   **Routing:** `go_router`
*   **Pattern:** Declarative routing with typed routes where possible.

## Key Libraries & Packages
### Media & UI
*   `lucide_icons`: Icon set (v0.257+).
*   `google_fonts`: Typography.
*   `cached_network_image`: Image caching.
*   `flutter_slidable`: Swipe actions in lists.
*   `country_picker`: Country selection UI.
*   `confetti`: UI celebration effects.

### Audio & Video
*   `just_audio`, `audio_service`, & `just_audio_background`: Radio streaming and audio playback.
*   `video_player` & `chewie`: Video message playback.
*   `record`: Audio recording.

### Location & Maps
*   `geolocator`: GPS handling.
*   `geocoding`: Reverse geocoding (Lat/Lng -> Address).
*   `flutter_google_places_sdk`: Places API integration.
*   `geoflutterfire_plus`: Geofenced queries for nearby discovery.

### Identity & QR
*   `qr_flutter`: Generating user and organization QRs.
*   `mobile_scanner`: High-performance QR scanning for P.o.C.T Level 3.

### File Handling
*   `image_picker`: Media selection.
*   `file_picker`: Document selection.
*   `path_provider`: Local filesystem access.
*   `syncfusion_flutter_pdfviewer`: In-app document viewing.

## Development Tools
*   `flutter_lints`: Static analysis.
*   `build_runner`: Code generation runner.
*   `mockito`: Automated testing mocks.
