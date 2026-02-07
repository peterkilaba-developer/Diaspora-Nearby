# Development Workflow

*   **Source of Truth:** The files in the `conductor/` directory represent the current state and mission of the project. **Step 0 of every task is to read these files.**

## Standard Commands

### Running the App
```bash
flutter run
```

### Code Generation
Run this whenever models or providers change (files using `@freezed`, `@JsonSerializable`, etc.):
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Analysis & Linting
Ensure code quality before committing:
```bash
flutter analyze
```

## Architectural Guidelines

### 1. Feature-First Structure
Code is organized by feature in `lib/features/`. Each feature folder typically contains:
*   `screens/`: UI Widgets (Pages).
*   `providers/`: Riverpod Providers (State Management).
*   `repository/`: Data Access Layer (API/Firebase calls).
*   `widgets/`: Feature-specific reusable widgets.

### 2. State Management (Riverpod)
*   Use `RepositoryProvider` for data access classes.
*   Use `StateNotifierProvider` or `AsyncNotifierProvider` for complex UI state.
*   Use `FutureProvider` or `StreamProvider` for data fetching.

### 3. Data Models
*   Models go in `lib/models/`.
*   Prefer immutable classes using `freezed` or `json_serializable`.
*   Include `fromRTDB` or `fromFirestore` factory methods for Firebase data mapping.

### 4. Chat System Specifics
*   **RTDB** is the source of truth for *messages* and *chats*.
*   **Firestore** is the source of truth for *users* and *static entity data*.
*   **Repository Restoration:** If modifying `ChatRepository`, ensure strict adherence to the existing multi-part structure or be careful not to introduce encoding errors.

## Context Maintenance
*   **Mandatory Review:** Before any implementation or refactor, verify that the proposed changes do not conflict with `product.md` or `tech-stack.md`.
*   **Continuous Updates:** Update `tracks.md` when starting or completing a major module. Update `tech-stack.md` if adding or removing dependencies.
*   **AI Protocol:** AI assistants MUST read the `conductor/` directory at the start of every session to ensure they are using the correct references and conventions.

## Current Task Status: Community Chat Integration
- [x] **Community Chat Integration**
    - [x] Add "Create Community Group" link to community chat "More menu".
    - [x] Add "Create Community Event" link to community chat "More menu".
    - [x] Add "Create Community Org/Business" link.
    - [x] Enable "Public Group" option for community groups.
    - [x] Context-aware creation flows (pass `communityId`).
