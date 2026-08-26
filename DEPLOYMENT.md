# FixNow Deployment

## Automated release pipeline

Pull requests and pushes to `main` run `.github/workflows/ci.yml`. It checks
static analysis, Flutter tests, Node tests, and committed secrets.
Never merge when a required check is failing.

Create separate GitHub Environments named `staging` and `production`. Configure
these variables in each environment:

- `FIXNOW_APPLICATION_ID`
- `FIXNOW_AUTH_API_URL`
- `FIXNOW_ADMIN_API_URL`
- `FIXNOW_FIREBASE_AUTH_DOMAIN`
- `FIXNOW_FIREBASE_PROJECT_ID`
- `FIXNOW_FIREBASE_STORAGE_BUCKET`
- `FIXNOW_FIREBASE_MESSAGING_SENDER_ID`
- `FIXNOW_FIREBASE_APP_ID`

Configure these protected environment secrets:

- `GOOGLE_SERVICES_BASE64`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_MAPS_API_KEY`
- `FIXNOW_FIREBASE_API_KEY`

Use a different Firebase project and server for staging. GitHub production
environment approval should be required. Run **Android signed release**
manually with an increasing version code. The workflow validates configuration,
runs all checks, builds signed APK/AAB files, and stores them as GitHub artifacts.

The pipeline creates artifacts only; it intentionally does not automatically
publish to Google Play.

## Android Play Store

1. Confirm the checked-in Firebase Android options still match project `fixnow-a6515`. Run `flutterfire configure` again whenever the Android application ID changes.
2. The default Android package is `com.fixnow.app`. To override it, set `FIXNOW_APPLICATION_ID` in `android/local.properties`, as a Gradle property, or as an environment variable.
3. Add release signing in `android/key.properties`:

   ```properties
   storeFile=../release.keystore
   storePassword=...
   keyAlias=...
   keyPassword=...
   ```

   Release builds intentionally fail when this file or any required signing
   value is missing. FixNow never falls back to the debug key for a Play Store
   artifact.

4. Add a real Google Maps API key with Android app restrictions by setting `GOOGLE_MAPS_API_KEY` in `android/local.properties`, as a Gradle property, or as an environment variable.
5. Configure launcher icons and adaptive icon assets.
6. Deploy the authenticated tracking/administration service and pass its HTTPS URL at build time. Device-localhost is intentionally not used as a production fallback:

   ```sh
   flutter build apk --release --dart-define=FIXNOW_ADMIN_API_URL=https://your-service
   ```

7. Build the Play Store bundle with the same API URL and map keys:

   ```sh
   flutter build appbundle --release
   ```

8. Upload the `.aab` to Play Console with privacy policy, data safety, screenshots, and production track settings.

## iOS App Store

1. Run `flutterfire configure` for iOS and commit `GoogleService-Info.plist`.
2. Set bundle identifier and signing team in Xcode.
3. Add APNs auth key to Firebase Cloud Messaging.
4. Add the Google Maps iOS API key in `AppDelegate.swift`.
5. Configure app icons and privacy manifest.
6. Build archive from Xcode or:

   ```sh
   flutter build ipa --release
   ```

7. Upload through Transporter or Xcode Organizer to App Store Connect.

## Production notes

- Move admin-only actions, nearest-technician assignment, revenue analytics, and idle alerts to Cloud Functions.
- Send push notifications from trusted Cloud Functions. Client writes to the `notifications` collection are intentionally blocked by the production rules.
- Implement WhatsApp approval through a verified WhatsApp Business webhook. Opening WhatsApp with a prefilled message is only a fallback and must not directly mutate approval state.
- Connect attendance selfies to a reviewed face-verification service before setting `faceMatchPassed` to true. The app currently records face verification as pending rather than claiming a match.
- Create Firestore composite indexes for user-specific booking queries ordered by `createdAt`.
- Restrict role assignment. Do not expose admin or technician self-registration in a public production build.
- Use Firebase App Check, Crashlytics, Performance Monitoring, and Remote Config before public launch.
- Store payment status and invoices in `bills`; compute revenue from paid bills, not booking state alone.
- Deploy Firestore rules and the indexes declared in `firestore.indexes.json` together.

## Rollback

1. Stop rollout in Play Console immediately when crash, login, booking, billing,
   or tracking alerts exceed the accepted threshold.
2. Promote the previous known-good artifact for users who have not updated.
   Android version codes cannot be reused, so a corrective release must use a
   higher code.
3. Roll back the Node service to the previous known-good Git commit in Render.
4. Keep timestamped copies of previously deployed Firestore and Storage rules.
   Validate restored rules against the Firebase emulator before deployment.
5. Export Firestore before schema migrations. Application rollback does not
   automatically undo data migrations.
6. Record the incident, affected release/version, time window, and recovery
   decision. Do not delete production evidence or logs during recovery.
