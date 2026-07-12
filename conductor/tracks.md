# Development Tracks

## ✅ Completed Tracks

### 1. Core Chat System
*   **Status:** Stable / Optimization Complete
*   **Features:** Direct, Group, and Community Chats.
*   **Capabilities:** Text, Image, Video, Audio, Document, Location messages.
*   **Optimization:** Optimistic UI (instant send), Local Caching (offline view), Media Previews, "UserChats" fan-out updates.
*   **Refinement:** Fixed scroll behavior, media reloading issues, and unread counts.

### 2. User Profile & Onboarding
*   **Status:** Stable / Refined
*   **Features:** Phone Auth, Profile Creation, Hometown/Host-town/Path selection, QR generation.
*   **Refinement:** Unified `UserProfileForm`, Profile Completeness tracking, Identity Levels 1-3.

### 3. DSP Economy & Trust System (P.o.S.A/P.o.C.T)
*   **Status:** Refined Model Implementation
*   **Features:** Points earning (messaging, referrals, shares, streaks), 6-Tier Trust Score (0-100) with 5 normalized factors (20 pts each).
*   **Refinement:** Constant 1.0x rewards, Genesis Gate (10,000 DSP), TGE Efficiency tiers (10-step decile scale: 10% per 10 points).

### 4. Community Governance & Treasuries
*   **Status:** Functional Framework
*   **Features:** Home Country & Continent Treasuries (10% Share), Collective Milestone triggers at 1 Million DSP earned by community members.

### 5. Professional Development Setup
*   **Status:** Complete (Feb 2026)
*   **Features:** Git Flow branching strategy, CI/CD pipeline with GitHub Actions, Interface documentation for core features, Testing framework with utilities and examples.
*   **Documentation:** CONTRIBUTING.md (workflow), test/README.md (testing guide), INTERFACE.md files (service contracts).


## 🚧 Active Tracks

### 1. Integration & Polish
*   **Focus:** Bridging the Governance UI with Chat (Pillar Elections menu), refining QR scanning UX, and ensuring cross-feature consistency.
*   **Recent Actions:** `UserProfileForm` consolidation, Election menu integration in chat.

### 2. Maintenance & Performance
*   **Focus:** Local caching optimization with Isar, Firebase Performance monitoring, and strict typing enforcement.

## 📅 Planned / Future Tracks

### 1. Advanced Notifications & Proximity
*   **Goal:** Deep integration of Push Notifications for chat and proximity-based community alerts.

### 2. Search & Discovery 2.0
*   **Goal:** Geofenced search for People, Communities, and Organizations using `geoflutterfire_plus`.

### 3. DFDI & Global Marketplace
*   **Goal:** Diaspora Foreign Direct Investment (DFDI) portal and P2P service marketplace.
