# Horilla Employee (Flutter)

Employee check-in / check-out app for Horilla HR. Uses **Riverpod** + **dio** against `/api/v1`.

## Features (this scaffold)

- Login (`POST /auth/login/`) with JWT access + refresh
- Automatic token refresh on 401
- Home screen matching the attendance UI (timer, check-in/out button, schedule card)
- Clock-in / clock-out (`/attendance/clock-in/`, `/attendance/clock-out/`)
- Sends GPS when company geofencing is enabled
- Bottom nav stubs: Attendance, Requests, Notifications, More

## Run

1. Start Horilla: `python manage.py runserver 0.0.0.0:8000`
2. From this folder:

```bash
flutter pub get
flutter run
```

### API base URL

On first launch the app asks for your ClockMe server (for example
`http://10.0.2.2:8000` on the Android emulator, or
`https://hr.yourcompany.com`). It is saved on the device and can be changed
later under **More → Server address**.

Live API tests / CLI tools can still pass a URL:

```bash
flutter test test/request_flow_api_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Ensure Django `ALLOWED_HOSTS` includes that host.

## Play Store (Android)

Application ID: **`com.codefest.clockme`**. Display name: **ClockMe**.

The ClockMe URL is entered in the app, so a dart-define is not required for store builds:

```bash
flutter build appbundle --release
```

The signed AAB is `build/app/outputs/bundle/release/app-release.aab`. Upload that in Play Console (not an APK). HTTP company LAN hosts are allowed; prefer HTTPS in production.

Signing uses the existing keystore in `ClockMe-KeyStore-Details/` via `android/key.properties` (gitignored). Back the keystore and credentials up offline. If you lose the upload key, you cannot ship updates until Google resets it via Play App Signing.

Play Console still needs a privacy policy URL (location + biometrics), a Data safety form, and listing assets in `store/play/`.

## Project layout

```
lib/
  core/           # config, theme, dio, secure storage
  features/
    auth/         # login + JWT session
    home/         # mobile home + punch
    shell/        # bottom navigation
    placeholders/ # stub tabs
```
