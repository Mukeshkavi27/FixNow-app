# FixNow Deployment

## Android Play Store

1. Run `flutterfire configure` and commit generated Firebase options plus `google-services.json`. The checked-in `firebase_options.dart` only contains working web options; Android and iOS intentionally show a configuration error until their Firebase apps are generated.
2. Set `applicationId` to your package, for example `com.fixnow.app`.
3. Add release signing in `android/key.properties` and `android/app/build.gradle`.
4. Add a real Google Maps API key with Android app restrictions.
5. Configure launcher icons and adaptive icon assets.
6. Build:

   ```sh
   flutter build appbundle --release
   ```

7. Upload the `.aab` to Play Console with privacy policy, data safety, screenshots, and production track settings.

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
