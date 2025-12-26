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
*   **Storage:** `firebase_storage` - Media assets (Images, Videos, Audio, Docs).
*   **Security:** `firebase_app_check`.
*   **Notifications:** `firebase_messaging` + `flutter_local_notifications`.

## Navigation
*   **Routing:** `go_router`
*   **Pattern:** Declarative routing with typed routes where possible.

## Key Libraries & Packages
### Media & UI
*   `lucide_icons`: Icon set.
*   `google_fonts`: Typography.
*   `cached_network_image`: Image caching.
*   `flutter_slidable`: Swipe actions in lists.
*   `country_picker`: Country selection UI.

### Audio & Video
*   `just_audio` & `audio_service`: Radio streaming and audio message playback.
*   `video_player` & `chewie`: Video message playback.
*   `record`: Audio recording.

### Location & Maps
*   `geolocator`: GPS handling.
*   `geocoding`: Reverse geocoding (Lat/Lng -> Address).
*   `flutter_google_places_sdk`: Places API integration.

### File Handling
*   `image_picker`: Media selection.
*   `file_picker`: Document selection.
*   `path_provider`: Local filesystem access.

## Development Tools
*   `flutter_lints`: Static analysis.
*   `build_runner`: Code generation runner.
