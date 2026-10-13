# Dastak Flutter mobile

Flutter source is in `lib/`; the original React app remains in the repository root.
Android/iOS identity: `com.dastak.app`. Material 3, Riverpod, GoRouter and Supabase.

## Setup

Validated SDK: Flutter 3.22.0, Dart 3.4.0. Android uses AGP 8.6.1, Gradle 8.14.3,
Kotlin 1.9.24, SDK 35 and JDK 17. This pins a compatible environment; it is not a
claim that these are the newest SDKs or meet every current store submission rule.

```
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=config/staging.json
```

Copy `config/example.json` to your ignored environment config and set only a
Supabase URL and client-safe publishable/anon key. Never add service-role keys.
`tools/prepare-local-config.ps1` copies only those two public values from the
existing web `.env.local` into ignored `config/local.json`. Without config the app
shows an explicit setup message. The environment is compiled into each artifact.

On this Windows host flutter.bat stalls. The equivalent SDK entry point works:

```powershell
& E:\flutter\bin\cache\dart-sdk\bin\dart.exe E:\flutter\bin\cache\flutter_tools.snapshot analyze
```

## Backend deployment

Read `docs/MIGRATION.md`, `docs/live-schema-audit.json` and `docs/ACCEPTANCE.md`.
Local PostgreSQL checks: `cd tools; npm ci; npm test`.
These tests emulate Supabase auth/storage schemas; no production data is touched.

Migration `../supabase/migrations/0010_mobile_security.sql` and updated
`../supabase/functions/place-order/index.ts` must be reviewed and deployed together.
The app checks `mobile_checkout_capabilities` before invoking checkout so a legacy
function cannot mistake a quote for an order. The migration must not be deployed
alone while the old checkout function still depends on public create_order.
The migration leaves `app_settings.mobile_checkout_enabled=false`. Only after
deploying the new Edge Function should an administrator set this JSON value to
`true`. Until then the native checkout stays unavailable, including during rollout.

Migration 0010 and place-order were deployed with explicit user approval on 13 October 2026; checkout capability is enabled. Migration 0011 now connects notifications to send-push using Vault. The migration ledger is still empty even
though 0001–0009 objects exist. **Do not run an unreviewed `supabase db push`: it
would try to replay initial schema migrations.** Reconcile the migration ledger
against the audited schema before future CLI migrations. No production reset,
seed or migration-ledger repair has been applied by this task.

A coordinated deploy needs the new SQL and place-order function, service-role key
available only in Edge Functions, and working GOOGLE_ROUTES_API_KEY. The latter
secret name exists but its stored value failed validation: no valid Google API key was found. A replacement key is required before checkout can calculate a route.
The upgraded function retains the existing web request shape but rejects unsafe
client-priced fallback operations. Review legacy web checkout before rollout.

## Android artifacts

```powershell
./tools/build-android.ps1 -Mode debug -Config config/local.json
./tools/build-android.ps1 -Mode bundle -Config config/production.json
```

Outputs: `build/app/outputs/apk/debug/app-debug.apk`, release APK and
`build/app/outputs/bundle/release/app-release.aab` as applicable. The low-memory
build script uses JDK 17 and two workers. Debug uses the debug signing identity.
For release add ignored `android/key.properties` with storeFile, storePassword,
keyAlias and keyPassword, using the **existing approved release key**. Without
this file release artifacts are unsigned, not upload-ready. Do not uninstall an
existing app to bypass a signing mismatch; that can erase user data.

## iOS

Open `ios/Runner.xcworkspace` on macOS after `flutter pub get` and `pod install`.
Select the approved Apple team, provisioning and signing for com.dastak.app.
Review Keychain entitlements for secure storage. Deployment target is iOS 13.
Auth callback scheme is com.dastak.app://auth/callback and must be allowlisted in
Supabase. Photo permission is for deliberate product/document selection.
No location/background-location permission is present.

```
flutter build ipa --dart-define-from-file=config/production.json
```

An iOS archive cannot be built or validated on this Windows machine. iOS launcher
art still needs brand/release review; generated platform assets are not a claim
of App Store readiness.

## Notifications and maps

In-app notifications read Supabase and update via Realtime. Native push is opt-in
and enabled in the new Android release APK. Firebase OAuth and an FCM validate-only request passed. The example config remains disabled by default. For other builds, provision Firebase Android
resources (google-services plugin/config), Apple Firebase plist, APNs key,
Push Notifications and remote-notification background mode. Test physical devices
and token cleanup. Existing server FCM secrets alone do not verify native delivery.
No fake push success, phone OTP, payment gateway, COD, ETA or live GPS is shown.

The map supports deliberate static pin selection with OpenStreetMap attribution.
For deployment configure a licensed tile provider in MAP_TILE_URL, review provider
terms and load capacity. The initial Rohtak viewport is not a saved location.

## Status and limitations

See `docs/STATUS.md` for executed checks and outstanding release gates.
Currency is paise; server resolves prices/options/stock/tax/delivery. A persisted
checkout request ID makes retries idempotent. Product removal is reversible
availability disable to preserve history. Admin enrollment uses existing user IDs.
Customer cancellation is not exposed because the reference has only an admin
cancellation workflow. Existing orders with legacy pricing are not rewritten.

