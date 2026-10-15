# MindSync Flutter — configuration

Authentication uses **Django JWT** (`LocalAuthService` + `ApiClient`). Firebase is not used.

## API base URL

Resolved in `lib/config/api_config.dart`:

| Build | How to set |
|--------|------------|
| **Production** | `--dart-define=BACKEND_BASE_URL=https://api.yourdomain.com` |
| **Web** | `--dart-define=WEB_API_BASE_URL=https://api.yourdomain.com` or same host on port 8000 |
| **Android emulator** | `http://10.0.2.2:8000` (automatic) |
| **Physical Android (USB)** | `adb reverse tcp:8000 tcp:8000` then app uses `http://127.0.0.1:8000` |
| **LAN** | `--dart-define=DEV_LAN_HOST=192.168.x.x` |

Example:

```bash
flutter run \
  --dart-define=BACKEND_BASE_URL=https://api.example.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_ID.apps.googleusercontent.com \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
```

## OAuth (Google Sign-In)

Register clients in Google Cloud Console, then pass:

- `GOOGLE_WEB_CLIENT_ID` — web client ID (also used as Android `serverClientId`)
- `GOOGLE_IOS_CLIENT_ID` — optional iOS client

See `lib/config/google_auth_config.dart`.

## Stripe

- `STRIPE_PUBLISHABLE_KEY` — required on mobile for Payment Sheet (`lib/utils/stripe_platform_mobile.dart`).

## Release bundle ID

Target application ID for store builds: **`com.mindsync.app`**.

Native projects may still show `com.example.frontend` until you rename in Xcode / `android/app/build.gradle` and update OAuth + signing. Kotlin package names under `com.example.frontend` can stay until a dedicated migration.

## Background monitoring (Android)

Two pipelines run in native code (`BackgroundUsageService`), not in Dart:

| Pipeline | Trigger | Duration | Face gate |
|----------|---------|----------|-----------|
| **Facial expression** (front camera) | Trackable app in foreground | **~20 s**, repeats every 5 min | ML Kit face must be visible before record; enrolled users must match on a video frame before upload |
| **Screen capture** (social apps) | Social app foreground + MediaProjection consent | **30 s** chunks | N/A (screen, not camera) |

Flutter passes JWT and API URL via `ScreenTimeService` → `configureTracker` after login.

## Dev commands

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
```
