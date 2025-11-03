# KeepInTouch

Stay in touch with the people that matter. KeepInTouch is a local‑first, privacy‑respecting reminder app that helps you keep relationships warm without the noise.

• Local data (SQLite). • Smart daily nudges. • Gentle snooze. • Beautiful calendar. • Optional read‑only device calendar overlay. 

## Highlights
- Local‑first and private: your contacts and interactions stay on your device.
- Material 3 design with smooth motion and haptics.
- Due and Upcoming contacts, swipe to Done or Snooze (with Undo).
- Month calendar with dot indicators, Today button, and device events overlay.
- Stats: interaction totals, who initiates, and a top‑people leaderboard.

## Screens
![collage](https://github.com/user-attachments/assets/b97730b9-1228-4855-9898-61c58581c1bd)

- Home – Due/Upcoming list with search and swipe
- Calendar – Monthly grid, details panel, and device overlays
- Stats – Leaderboard and initiator breakdown
- Settings – Reminders, haptics, theme presets, calendar toggle, export

## Quick start
```powershell
# From this folder
flutter pub get
flutter run
```

Requirements
- Flutter (stable) and Android SDK installed; `flutter doctor` is green.

## Build & release (Android)
Generate an app bundle for Play Store:
```powershell
flutter build appbundle --release
```

Signing
- Update `android/app/build.gradle.kts` to use your release keystore (replace the debug signingConfig). 
- Official guide: https://docs.flutter.dev/deployment/android

Permissions
- Notifications (Android 13+): `POST_NOTIFICATIONS`
- Device calendar (optional, read‑only overlay): `READ_CALENDAR`

Privacy
- All app data (people, interactions, special dates) is stored locally in SQLite. Export to JSON is available in Settings.

## Tech
- Flutter (Material 3), Google Fonts, subtle animations & haptics
- SQLite (sqflite), SharedPreferences
- WorkManager for daily reminders; flutter_local_notifications for delivery
- device_calendar + permission_handler for the optional read‑only overlay

## Credits
Built by Nassim, with GitHub Copilot assisting on implementation, UX polish, and calendar integration.

## License
Choose a license (e.g., MIT) and add a LICENSE file to this folder.
