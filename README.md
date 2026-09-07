# Smart Task Manager

An offline-first task management application for Android & iOS built with Flutter. Demonstrates clean architecture, local data persistence using Drift (SQLite), reactive state management with Riverpod, Dio HTTP client with custom interceptors, and Firebase authentication with Firestore user profile synchronization.

## Features

### Offline-First Architecture
- **Local SQLite Database (Drift)**: The local SQLite database acts as the single source of truth. Task operations (create, update, toggle completion, delete) reflect immediately in the UI.
- **Background Synchronization**: Local changes track their synchronization status (`synced`, `pending_create`, `pending_update`, `pending_delete`). When connectivity is restored, pending operations automatically push to the remote FastAPI backend and fetch latest remote updates.
- **Connectivity Monitoring**: Real-time network monitoring using `connectivity_plus` with an offline status banner.

### Authentication & Profile
- **Firebase Authentication**: Email and password sign in, registration, and persistent user session.
- **Firestore User Profile**: User profiles stored under `users/{userId}` tracking display name, email, account creation date, and theme preference.
- **Local Fallback Mode**: Graceful local session fallback if Firebase credentials are not yet configured.

### Task Management & REST API
- **FastAPI Backend Integration**: Base URL `https://taskmanager.uat-lplusltd.com`.
- **Dio Client**: Auto-injects `user_id` query parameter on all requests and maps network errors into structured domain exceptions.
- **Search & Filter**: Real-time debounced title search (300ms) with client-side status filtering (All, Pending, Completed).
- **Sorting**: Multi-parameter sorting by Created Date, Due Date, or Priority (High, Medium, Low).
- **Pagination**: Infinite scroll pagination using `skip` and `limit=10`.
- **Pull to Refresh**: Manual bidirectional synchronization trigger.

### UI & Theming
- Material 3 theming with dynamic Light and Dark mode toggle.
- Theme preference synced to Firestore and persisted locally.
- Reusable UI component library (buttons, inputs, dialogs, badges).

## Project Architecture

```
lib/
├── app.dart                                         # Root application widget
├── main.dart                                        # Entry point & dependency injection
├── core/
│   ├── constants/                                   # App constants & sync status enums
│   ├── database/                                    # Drift SQLite database & table definitions
│   ├── errors/                                      # Custom exception hierarchy
│   ├── network/                                     # Dio client & connectivity service
│   ├── storage/                                     # Hive key-value service
│   ├── theme/                                       # Material 3 light/dark themes
│   └── widgets/                                     # Reusable app-wide widgets
└── features/
    ├── auth/                                        # Authentication domain, data & screens
    ├── profile/                                     # User profile, settings & theme controller
    ├── splash/                                      # Splash screen & session routing
    └── tasks/                                       # Task models, repository, notifier & UI
```

## Getting Started

### Prerequisites
- Flutter SDK managed with [FVM](https://fvm.app/) (pinned to `3.47.0`)
- Dart SDK `^3.13.0`

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Azeem-dev14/smart_task_manager.git
   cd smart_task_manager
   ```

2. Install dependencies:
   ```bash
   fvm flutter pub get
   ```

3. Run the application:
   ```bash
   fvm flutter run
   ```

### Code Quality & Tests

- Static code analysis:
  ```bash
  fvm flutter analyze
  ```

- Run unit and widget tests:
  ```bash
  fvm flutter test
  ```

### Release Build

To build the release APK for Android:
```bash
fvm flutter build apk --release
```
The output binary will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`
