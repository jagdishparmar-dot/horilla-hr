# ClockMe Play Store checklist

Application ID: `com.codefest.clockme`  
Version: `pubspec.yaml` → `1.0.3+6` (name `1.0.3`, versionCode `6`)

## Build the upload bundle

The ClockMe server URL is entered in the app on first launch (and under
**More → Server address**). A dart-define is not required for store builds.

```bash
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab`.

## Signing

Uses the existing upload key in `ClockMe-KeyStore-Details/`:

- Keystore: `ClockMe-KeyStore-Details/@jagdishparmar__checkin-mobile-keystore.bak.jks`
- Passwords / alias: `ClockMe-KeyStore-Details/@jagdishparmar__checkin-mobile-keystore-credentials.md`
- Gradle reads them via `android/key.properties` (gitignored)

Turn on **Play App Signing** when you create the app. Keep a backup of the keystore and credentials; losing the upload key blocks updates.

## Play Console listing

Upload from `store/play/`:

- High-res icon: `icon-512.png` (512×512)
- Feature graphic: `feature-graphic-1024x500.png` (1024×500)

Phone screenshots (at least 2) still need to be captured from a device or emulator.

## Data safety (declare in Play Console)

ClockMe does **not** use advertising ID (permission removed). Typical declarations:

| Data | Collection | Why |
| --- | --- | --- |
| Location (precise / approximate) | Yes, on device + sent to your ClockMe server when geofencing is on | Check-in / check-out |
| Email / name / employee profile | Yes, from ClockMe | Account |
| Photos / files | Only if the user attaches a document | Requests / profile |
| Biometrics | On device only (app lock) | App lock |

You must publish a privacy policy URL that covers location and biometrics.

## After first upload

Bump `version:` in `pubspec.yaml` for every store update (`1.0.4+7`, then `1.0.5+8`, …). Play rejects reuse of the same versionCode.
