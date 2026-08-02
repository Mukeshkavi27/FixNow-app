# FixNow release-readiness audit

Audit date: 2026-07-28 (Asia/Kolkata)

## Current verdict

**NO-GO for Play Store production release.** The application code builds and its
current automated suites pass, but the Android production identity, signing,
Maps credential, Firebase Android registration, push delivery, physical-device
background tracking, and client Socket.IO integration are not yet verified.

## Evidence completed

| Check | Result | Evidence |
| --- | --- | --- |
| Flutter static analysis | PASS | `flutter analyze --no-pub`: no issues |
| Flutter automated suite | PASS | 71 tests |
| Tracking/admin backend suite | PASS | 36 tests |
| Android release bundle compilation | PASS WITH BLOCKERS | 49.4 MB AAB built, but Gradle fell back to debug signing |
| Customer dashboard | PASS | Live browser session rendered signed-in customer dashboard and services |
| Customer profile | PASS | Live browser session rendered customer name, phone, email and account actions |
| Customer sign-out | PASS | Live browser session returned to login page |
| Branch-admin sign-in and role routing | PASS | `cbeadmin@gmail.com` routed to Coimbatore branch-admin overview |
| Branch isolation indicator | PASS | UI displayed branch lock for `coimbatore-fixnow` |
| Branch booking counters and queues | PASS | Live UI showed 6 ongoing, 2 unassigned and 4 closed |
| Assignment eligibility picker | PASS | Live UI offered only a free technician |
| Full booking lifecycle regression | PASS (previous disposable run) | Customer arrival confirmation, estimate, approval, repair, bill, cash payment, branch-admin closure, super-admin visibility and customer paid bill were observed |
| Assignment transaction and realtime mapping | PASS | Covered by repository implementation and backend realtime tests |
| Attendance reminder schedule | PASS | Backend tests cover 09:00, 09:10, 09:20, 09:30 and 09:40 IST |
| Automatic absence | PASS | Backend test covers 09:45 IST and `Not Marked` reason |
| Active-job lock lifecycle | PASS | Lock is now released atomically on reject, hold and completion, and recreated safely on resume; rules compiled and deployed |
| Attendance FCM dispatch path | PASS (automated) | Technician token registration is initialized and backend test covers scheduler -> token -> FCM send -> delivery receipt persistence |
| Release signing safety | PASS | Release builds now fail instead of silently using the debug key |

## Confirmed production blockers

1. `android/key.properties` is missing. Release builds now stop with an explicit
   error rather than generating an unsafe debug-signed artifact.
2. `FIXNOW_APPLICATION_ID` is missing; the build uses the placeholder/default
   `com.fixnow.app`.
3. `GOOGLE_MAPS_API_KEY` is missing, so Android mapping/navigation cannot work.
4. `android/app/google-services.json` is missing.
5. `DefaultFirebaseOptions.android.appId` contains a web Firebase app ID
   (`:web:`), not an Android Firebase app ID (`:android:`). Android FCM cannot be
   certified until the correct Android Firebase app is registered.
6. The Flutter client has no Socket.IO client dependency or connection code.
   Firestore streams currently provide UI realtime updates, while the backend
   Socket.IO events are not consumed by the app.
7. Socket reconnect snapshots use unbounded historical booking/attendance
   queries. This will degrade as public data grows.
8. Camera/selfie, foreground/background GPS, Android permission flows, physical FCM push
   receipt, process restart, and network handoff have not been proven on a
   physical Android device.
9. No measured 50-technician load/soak result exists yet. Unit tests are not a
   substitute for load evidence.

## Release gate

Do not upload the current AAB. A production candidate is eligible only after the
blockers above are resolved and the full customer -> branch admin -> technician
-> customer payment -> monitoring -> super-admin workflow passes on a signed
Android internal-test build.
