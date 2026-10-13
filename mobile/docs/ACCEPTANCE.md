# Device and staging acceptance checklist

Automated local SQL tests are not a substitute for the deployed Supabase gateway,
Storage, Google Routes, Realtime, native permission and email callback tests.
The user confirmed that no staging backend/test accounts currently exist.
Do not place test orders or submit fabricated payment references on production.

Create a separate staging project, apply checked-in migrations in order, deploy
place-order, configure its Google Routes secret, and create four role accounts
plus a second customer/vendor. Use staging-only product and inventory fixtures.

1. Customer login, logout, relaunch/session restoration, signup confirmation and
   password-recovery callback. Check email service/rate limits.
2. Search/category navigation, empty store/menu, network failure and retry.
3. Bag quantity bounds, stock/price changes, store switching, options and restart.
4. Save/edit/delete address and explicitly select a map pin; no permission prompt
   or background GPS request. Manual coordinate fallback works with map offline.
5. Quote subtotal/tax/fee matches server. Double tap submits once. Kill app after
   submission and recover the same attempt. Change price after quote: reject and
   require review. Confirm inventory reserves once.
6. Real staging payment reference submission stays under review; unrelated user
   cannot read/verify it. Admin review is based on actual credited payment only.
7. Vendor creates/edits/disables product and options, uploads a photo; customer
   store reflects it. Other vendor's writes fail at database/Storage layer.
8. Vendor accepts paid order, prepares, marks ready. Invalid transitions fail.
9. Approved online partner accepts; second partner loses race. Pickup → in
   delivery → delivered yields one earnings entry. Suspended partner cannot act.
10. Partner submits private document. Other users cannot fetch it. Admin signs a
    short-lived URL and approves/rejects; partner cannot self-approve.
11. Admin store/member/partner/rate/settings changes persist and are audited.
    Non-admin direct RPC/table calls are rejected.
12. Realtime updates on two devices, reconnect, pull-to-refresh fallback, dispose
    subscriptions after leaving screen. Offline mutations surface errors.
13. Android small phone/tablet and large text; iOS safe area, keyboard, back/swipe.
14. Firebase/APNs token registration, refresh, opt-out, foreground inbox,
    background push, terminated launch, account switching and notification links.
15. Verify release signatures and upgrade from existing com.dastak.app install.

Run opt-in auth/catalog integration test only against staging:

```
flutter test integration_test/staging_test.dart -d DEVICE_ID --dart-define-from-file=config/staging-test.json
```

The staging test config additionally supplies TEST_CUSTOMER_EMAIL and
TEST_CUSTOMER_PASSWORD; keep it out of source control and release builds.
