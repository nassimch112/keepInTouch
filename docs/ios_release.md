# iOS release notes

> iOS support is optional and requires a Mac for building/signing.

## Targets & bundle id
- Open `ios/Runner.xcworkspace` in Xcode.
- Set your Bundle Identifier (e.g., com.yourname.keepintouch).
- Set Team (signing) and ensure a valid provisioning profile is selected.

## Versioning
- Keep version in `pubspec.yaml` in sync. Flutter will map it to iOS `CFBundleShortVersionString` and `CFBundleVersion`.

## Signing & capabilities
- Ensure automatic signing is enabled for simplicity (or manage profiles manually).
- Add capabilities only if needed. This app uses:
  - Push notifications: Not required; local notifications only.
  - Calendars: Read-only device calendar overlay (no write entitlements needed).

## Build
- From project root:
```
flutter build ipa --release
```
- Alternatively, build in Xcode: Product → Archive, then distribute via Organizer.

## App Store Connect
- Create an App record with the same Bundle ID.
- Upload your build with Xcode Organizer or `Transporter`.
- Fill in listing (screenshots, description, privacy policy).

## Privacy
- This app stores data locally. No third-party analytics or tracking.
- If you publish to App Store, include a privacy policy link consistent with the README.
