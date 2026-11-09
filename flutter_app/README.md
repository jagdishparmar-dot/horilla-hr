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

Default (Android emulator → host):

`http://10.0.2.2:8000/api/v1`

Override at build/run time:

```bash
# iOS simulator
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# Physical device (use your PC LAN IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api/v1
```

Ensure Django `ALLOWED_HOSTS` includes your host/IP (local `.env` already allows `localhost,127.0.0.1`).

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
