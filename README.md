# avtoservis

Flutter application with three app variants:

- GoFix: `com.avtoservis.app`
- GoFix ustalar: `com.avtoservis.owner`
- GoFix admin: `com.avtoservis.admin`

## Codemagic iOS setup

1. Create or connect the GitHub repository in Codemagic.
2. Add Apple Developer signing credentials in Codemagic under **User settings > Codemagic UI > Teams > Code signing identities**. Do not commit `.p8`, `.p12`, or provisioning profiles.
3. Add these encrypted environment variables to the Codemagic environment group:
	- `FIREBASE_USER_PLIST_BASE64`
	- `FIREBASE_OWNER_PLIST_BASE64`
	- `FIREBASE_ADMIN_PLIST_BASE64`
4. Each variable must contain the Base64 contents of the matching Firebase `GoogleService-Info.plist` for its bundle ID.
5. Start `ios-user`, `ios-owner`, or `ios-admin` from `codemagic.yaml`. The resulting IPA is published as a workflow artifact.

The iOS app icon is generated from `assets/app_icon.png`, the same source used for Android.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
