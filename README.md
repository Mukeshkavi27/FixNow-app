# FixNow

Flutter/Firebase foundation for a home appliance service management platform.

## What is included

- Material 3 responsive UI with light and dark themes.
- Single Firebase Authentication login with role-based routing.
- Clean Architecture inspired feature folders.
- Firestore repositories for users, bookings, estimates, bills, reviews, attendance, notifications, technician locations, and analytics.
- Customer, Technician, and Admin dashboards.
- Booking flow with optional image upload.
- Live tracking hooks using Google Maps and Geolocator.
- Firebase Storage upload paths for profile, attendance, and service photos.
- Firebase Cloud Messaging token registration and notification records.
- Android and iOS deployment notes.

## Current release blockers

- Generate Android and iOS Firebase app credentials with `flutterfire configure`.
- Configure Android and iOS Google Maps SDK keys before release.
- Deploy the included Firestore and Storage rules and verify them with the Firebase Emulator Suite.
- Add trusted Cloud Functions for push notifications, nearest-technician assignment, WhatsApp webhooks, analytics aggregation, and idle-alert delivery.
- Integrate a reviewed face-verification provider. Attendance currently stores face matching as pending.

## Setup

1. Install Flutter stable and run `flutter doctor`.
2. Create a Firebase project.
3. Enable Authentication, Cloud Firestore, Firebase Storage, and Cloud Messaging.
4. Install FlutterFire CLI and run:

   ```sh
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

5. Add Google Maps keys:
   - Android: `android/app/src/main/AndroidManifest.xml`
   - iOS: `ios/Runner/AppDelegate.swift`
6. Run:

   ```sh
   flutter pub get
   flutter run
   ```

## Firestore collections

`users`, `bookings`, `attendance`, `estimates`, `bills`, `reviews`, `notifications`, `technician_locations`, `analytics`.

## Store deployment

Android: configure `android/app/build.gradle`, signing config, app icon, package name, privacy policy, and release build.

iOS: configure bundle identifier, Apple signing, APNs key for FCM, app icon, privacy manifest, and archive through Xcode/App Store Connect.
