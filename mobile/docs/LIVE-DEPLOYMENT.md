# Live deployment — 13 October 2026

User explicitly approved migration 0010 and Edge deployment, including the
temporary checkout interruption risk. Its rollback-only live validation passed
before the actual deployment. No existing production orders were deleted or reset.

## Completed

- 0010 SQL applied; checkout Edge deployed; capability version 1 enabled.
- 0011 SQL applied; notification trigger reads webhook URL/token from Vault.
- send-push deployed with its own secret authentication; gateway JWT checking is
  disabled because the database webhook uses that shared secret.
- Android Firebase configuration matches com.dastak.app / dastak-5ad52.
- Native notification channel, startup token restoration, token refresh and
  foreground alerts implemented; release build has PUSH_ENABLED=true.
- Existing Dastak release signing identity reused; APK signature verified.
- Firebase OAuth, project match and FCM HTTP validate_only request passed. This
  verifies server permissions without sending a notification to a real user.
- The same diagnostic request also passed through database pg_net using the
  Vault URL/token: HTTP 200, no timeout. No user notification was created.
- Live Realtime websocket broadcast roundtrip passed on an isolated channel.
  orders/products/notifications/delivery_assignments are published. No database
  records were changed by that probe.
- Flutter analyzer clean; 16 Flutter tests and 23 local PostgreSQL tests passed.

## Still required

- Existing Google Routes secret was malformed (invalid HTTP-header characters
  and no valid Google API key). User is providing a replacement in ignored
  config/routes.private.env. Until a successful route probe, checkout is deployed
  but cannot complete distance calculation. Never substitute fabricated distance.
  After saving the key, run tools/configure-routes.ps1 to upload only that secret
  and verify a real road-route request without creating an order.
- Real Android device notification receipt, foreground/background/terminated
  handling and complete role workflows remain unverified; no device was detected
  at the last ADB check. User said they will connect a phone.
- No staging/test accounts exist. Local SQL workflow checks do not establish
  live customer/vendor/partner/admin end-to-end acceptance or payment settlement.
- iOS signing, APNs and device/archive verification require macOS and Apple setup.

The old debug APK and unsigned AAB predate this deployment and have push disabled.
Use the new signed release APK. Future DB CLI pushes must reconcile the existing
empty migration ledger; do not replay 0001–0011 against the current database.

Secrets remain outside tracked source. Do not publish config/*.private.*,
android/key.properties, native Firebase configuration or signing material.
