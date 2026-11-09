# Flutter employee check-in/out app

## Goal
Scaffold `flutter_app/` for Horilla employees: login + home attendance UI (per attached screenshot), wired to JWT REST API. Other tabs are placeholders.

## Stack
- Flutter 3.x
- Riverpod (state)
- dio (HTTP + JWT refresh interceptor)
- flutter_secure_storage (tokens)
- geolocator (optional coords when geofence enabled)

## API
- Base: configurable, default Android emulator `http://10.0.2.2:8000/api/v1`
- `POST /auth/login/` → access, refresh, employee
- `POST /auth/refresh/`
- `GET /mobile/home/`
- `POST /attendance/clock-in/` (JSON latitude/longitude when fence on)
- `POST /attendance/clock-out/`

## Screens
1. Login
2. Shell with bottom nav: Home | Attendance | Requests | Notifications | More
3. Home matches screenshot: greeting, timer, check-in/out button, times, work schedule card

## Out of scope
Full attendance history, leave requests, push, face detection UI.
