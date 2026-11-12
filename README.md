# Gphotos

On-device Android gallery: photo grid with slide-to-select, high-resolution viewer, non-destructive
editor, face grouping and an encrypted private vault. Flutter, Android only. Nothing is uploaded:
every feature runs on the phone.

## Build

Requirements: Flutter stable (tested on CI with the current stable; Gradle 9.5, AGP 9.3.1, Kotlin 2.4.20), JDK 17, Android SDK.

```bash
flutter create --platforms=android --org com.gphotos --project-name gphotos .   # adds the Gradle wrapper only
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The APK is at `build/app/outputs/flutter-apk/app-debug.apk`.
GitHub Actions (`.github/workflows/build.yml`) runs analyze, the tests and the debug build on every push
and uploads the APK as the `Gphotos-debug-apk` artifact.

## Features and how they work

| Area | What it does | Where |
|---|---|---|
| Library | Loads the whole photo library page by page (500 at a time), keeps only lightweight handles in memory; thumbnails are cached in a 40 MB LRU | `lib/core/media_library.dart`, `lib/widgets/thumb.dart` |
| Multi-select | Tap to toggle in selection mode; long-press + slide selects a range, starting on a selected photo deselects; sliding back shrinks the range; auto-scroll near the top / bottom edge; haptic tick per change; Select all; Back clears the selection | `lib/selection/` |
| Grid | Pinch with two fingers to change columns (2-6), spacing and square / full thumbnails in Settings | `lib/selection/photo_grid.dart` |
| Viewer | Screen-sized preview first; when zoomed in, the visible region is decoded natively with `BitmapRegionDecoder` in 512 px tiles at the sample size the zoom needs (EXIF rotation handled), so every region of a large photo is shown at full resolution without decoding the whole bitmap; double-tap zoom, swipe between photos, swipe down to close, info sheet | `lib/viewer/`, `MainActivity.kt` |
| Editor | Interactive crop (drag corners, edges, frame; free or 1:1, 4:3, 3:4, 16:9, 9:16, 3:2, original), rotate left / right, flip horizontal / vertical, resize (width / height, keep aspect), exposure, brightness, contrast, saturation, warmth, 7 filters, auto enhance (levels), long-press to compare. Preview and export use the same colour matrix. Export decodes the original at full resolution in a background isolate and saves a **new** photo (JPEG 95 or PNG); the original is never changed | `lib/editor/` |
| People | ML Kit face detection on-device over the whole library (resumable, progress, pause), faces grouped by an appearance descriptor, name people, merge, split, move faces, set cover, remove wrong detections, hide people; everything saved to app storage and kept across rescans | `lib/faces/` |
| Vault | Photos are encrypted with AES-256-GCM (1 MB chunks, authenticated, truncation detected) with a random 256-bit key kept in `flutter_secure_storage` (EncryptedSharedPreferences, Android Keystore). PIN hashed with PBKDF2-HMAC-SHA256 (120 000 iterations, random salt), lockout after 5 wrong tries, optional biometric unlock, auto-lock when the app is hidden, FLAG_SECURE while open. Import encrypts, then decrypts and compares SHA-256 before anything is deleted, then asks separately whether to delete the originals. Restore saves to the gallery first and only then removes the vault copy. Thumbnails and the index are encrypted too; no plaintext file is written | `lib/vault/` |
| Share / delete | Share any number of photos in one share sheet; delete always asks first (and Android 11+ shows its own confirmation); only ids the system reports as deleted are removed from the app | `lib/core/file_ops.dart` |
| Storage | Scans every photo (progress, cancel): exact duplicates (same size and same SHA-256), photos over 5 MB, screenshots | `lib/screens/storage_page.dart` |
| Customization | Theme (system / light / dark), accent colour, columns, spacing, thumbnail style, tab labels, start tab, gestures (slide-select, pinch columns, swipe-down close, haptics), all persisted | `lib/core/app_settings.dart`, `lib/screens/settings_page.dart` |
| Icon | Launcher icons generated from the supplied artwork: legacy square + round icons for all densities and an adaptive icon (foreground + #0A0F2C background) | `tool/make_icons.py`, `android/app/src/main/res/mipmap-*` |

## Limits (honest list)

- **Face grouping is approximate.** Detection uses Google ML Kit (on-device). There is no trained
  face-recognition model in the app, so grouping compares aligned grey face patches (cosine distance).
  Expect some mixed or split groups and fix them with Merge / Split / Move. A recognition model (for
  example a MobileFaceNet TFLite file) would be needed for accurate grouping.
- **Face scanning runs while the app is open** (it is not an Android WorkManager job). It resumes
  where it stopped the next time you tap Continue scan.
- **Biometrics unlock the app's vault screen**; the vault key is protected by the Android Keystore but is
  not bound to a biometric authentication (the PIN path must work without biometrics).
- **No AI image tools.** Background removal, AI upscaling, colourisation and object eraser are listed as
  not supported in Tools. "Auto enhance" is a classic levels adjustment.
- The vault is device-bound and excluded from Android backups: uninstalling the app or clearing its data
  destroys the vault contents. Restore photos to the gallery before uninstalling.
- Images only (no videos).
- Duplicate hashing reads each candidate file fully; on very large libraries the storage scan takes a
  while (it can be cancelled).

## Project layout

```
lib/
  main.dart                 app, theme, bottom navigation
  core/                     settings, media library, share / delete helpers
  selection/                selection model (pure) + photo grid
  viewer/                   tiled high-res viewer + region decoder channel
  editor/                   edit maths (pure), crop overlay, editor screen
  faces/                    face model (pure), store, scanner, screens
  vault/                    crypto (pure), store, import flow, screens
  screens/                  home, photos, albums, storage, slideshow, tools, settings
android/                    Gradle (Kotlin DSL), manifest, MainActivity.kt, icons
test/                       unit + widget tests
tool/make_icons.py          regenerates the launcher icons from tool/icon/gphotos_icon_source.png
```

## Permissions

`READ_MEDIA_IMAGES` (+ `READ_MEDIA_VISUAL_USER_SELECTED` for partial access on Android 14),
`READ_EXTERNAL_STORAGE` (Android 12 and older), `WRITE_EXTERNAL_STORAGE` (Android 9 and older),
`ACCESS_MEDIA_LOCATION` (photo location in the info sheet), `USE_BIOMETRIC`, `VIBRATE`.
