# Verification status — 13 October 2026

**Update:** See [LIVE-DEPLOYMENT.md](LIVE-DEPLOYMENT.md) for the newer approved
deployment and signed Firebase-enabled APK. The historical build report below
describes the earlier debug APK/unsigned AAB; its undeployed/push-disabled gates
have been superseded. The Google Routes key and device acceptance remain open.

## Implemented source

Native Flutter Android/iOS project, Supabase repositories, Riverpod state,
GoRouter routes/role guards, secure session persistence, email/password signup,
login and recovery, customer store/menu/options, persisted single-store cart,
manual addresses and selected pins, server quote/idempotent checkout, orders and
UPI reference review, vendor store/menu/options/photo/order management, partner
availability/offers/delivery/documents/earnings, mobile admin stores/membership,
payments/partners/document review/rates/settings/audit and notifications.

All visible data comes from Supabase or a local persisted user cart; no production
catalog, earnings, location, ETA or payment success is fabricated. No GPS SDK or
location permission is included. Original React files were not rewritten by this
migration task; pre-existing user modifications remain intact.

## Executed checks

- Flutter dependency resolution: passed.
- Flutter analyzer: passed, no issues.
- Flutter unit/repository/widget suite: **16 tests passed**, including small-phone
  cart interactions, login validation and forbidden-role rendering.
- Local embedded PostgreSQL suite: 23 checks passed, including real SQL/RLS,
  server pricing, stock reservation, retry idempotency, cross-user access,
  role/approval restrictions, payment verification, state transitions and rates.
- Android debug APK: built successfully with JDK 17 and low-memory Gradle settings.
- Android release AAB: built successfully; unsigned, not ready for Play upload.
- APK manifest inspected: com.dastak.app, Dastak label, min SDK 23, target SDK 35,
  expected launch activity; **no foreground or background location permission**.
- Existing live vendors/products endpoint: HTTP 200, read-only check.
- Live schema/policies/function metadata: audited and saved in live-schema-audit.json.
- Android devices: none connected. Device startup/navigation not executed.
- iOS build/archive: not executed; macOS/Xcode unavailable.

Initial builds failed on Java/Kotlin target mismatch and then native JVM memory
exhaustion. Targets were aligned, Kotlin cross-drive incremental compilation was
disabled, and Gradle memory/workers reduced; the resulting debug build succeeded.
Old plugin Java 8/deprecation warnings remain in build logs.

## Not release-ready / external gates

1. New SQL migration and updated Edge Function are **not deployed**. Live checkout
   stays unavailable in Flutter until coordinated deployment and explicit enabling
   of app_settings.mobile_checkout_enabled. Existing migration history has no
   tracked versions; blindly replaying all migrations would conflict with live tables.
2. No staging project/test accounts exist (confirmed by user). Four-role deployed
   acceptance, concurrent requests through PostgREST, real payment review, email
   callbacks, Storage upload authorization and Realtime delivery remain unverified.
3. GOOGLE_ROUTES_API_KEY and FCM server secret names exist, but routing billing,
   native Firebase/APNs configuration and real-device push have not been tested.
4. Native push remains disabled; iOS signing/entitlements, launcher art and store
   compliance require release review. Generated iOS source is not an archive.
5. Release artifacts without android/key.properties are unsigned. Existing web
   signing materials were not copied or altered. No store publication occurred.
6. Product removal uses disable rather than physical deletion. Account enrollment
   uses registered user IDs. No public admin registration, phone OTP, gateway/COD,
   payout execution or customer cancellation workflow is represented as available.
7. Some administrative records use schema-checked JSON editing boundaries rather
   than separate immutable Dart model classes for every table. UI search within a
   store filters loaded pages; cross-store product search is not implemented.

See ACCEPTANCE.md for the full release checklist and README.md for commands.
