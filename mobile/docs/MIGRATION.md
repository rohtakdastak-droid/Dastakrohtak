# Flutter migration audit — 13 October 2026

Reference: README.md, src routes and API call sites, Supabase migrations 0001–0009,
four Edge Functions, Capacitor Android identity. Existing React work is retained.
No production migration has been applied. The live schema was subsequently audited
read-only in docs/live-schema-audit.json; tables and the targeted functions match
the checked-in contracts. A legacy payment-QR policy allowed all authenticated
users to upload/delete QR files; the new migration removes that access.

Schema uses integer paise, role `delivery`, required address coordinates, nullable
stock, single-vendor carts. Categories belong to vendors; options are additive
without required group rules. COD is unavailable. Delivery enrollment is by admin.

## Priority checklist

1. Separate Flutter Android/iOS project, Riverpod state, GoRouter, Supabase.
2. Close direct order insertion, client distance/option pricing, stock/minimum gaps.
3. Protect profile roles, partner approvals, document verification and admin views.
4. Auth, discovery, persisted cart, addresses/pins, quote/checkout, UPI, orders.
5. Membership-scoped vendor product/options/image and order management.
6. Partner offers, active delivery, documents, earnings and online state.
7. Admin vendors/membership, payments, partners/documents, settings/rates/audit.
8. Unit/widget/repository tests, staging SQL suite, platform builds.

## Feature mapping

| React route | Flutter route | Contract |
|---|---|---|
| /login | /login, /reset | Auth and secure session storage |
| / | / | vendors/category/search |
| /vendor/:id | /store/:id | products/options |
| /cart | /cart | persisted cart |
| /checkout | /checkout | saved addresses, place-order quote/create |
| /orders/:id | /orders/:id | orders/items/history/payment RPCs |
| /profile | /profile, /addresses | profiles/user_addresses |
| NotificationBell | /notifications | notifications/optional FCM |
| /vendor | /vendor | membership stores and order access |
| /vendor/menu | /vendor/store/:id/menu | products/options/storage |
| /vendor/profile | /vendor/store/:id | store settings |
| /vendor/orders | /orders | RLS + status RPC |
| /partner | /delivery | available and active delivery RPCs |
| /partner/earnings | /delivery/earnings | earnings summary/history |
| /partner/profile | /delivery/profile | profile/private documents |
| /admin | /admin | authorized metrics |
| /admin/vendors | /admin/vendors | vendors/membership RPC |
| /admin/products | store menu editor | admin selects vendor |
| /admin/orders | /orders | cancel RPC |
| /admin/payments | /admin/payments | verify RPC |
| /admin/partners | /admin/partners | approval/documents |
| /admin/settings | /admin/settings | payment/app settings/rates |
| /admin/audit | /admin/audit | audit logs |

## Architecture

Feature-first widgets and Riverpod state; repositories own database calls. Typed
commerce models preserve paise. Role guards are UX; SQL must enforce permissions.
Realtime invalidates queries and is disposed. Tables paginate in pages of 30.
Mutations do not auto-retry. Checkout attempt IDs persist for safe explicit retry.

Package versions target installed Flutter 3.22/Dart 3.4, not latest releases.
Package pages reviewed on pub.dev: Supabase/Riverpod/uuid (MIT), GoRouter,
shared_preferences, secure_storage, image_picker, flutter_map, Firebase and
url_launcher (BSD), latlong2 (Apache). Resolved notices appear in Flutter Licenses.
pub resolution/analyzer/build results provide actual compatibility evidence.

## Existing blockers

0009 permits client-priced direct orders. Original create_order trusts option
deltas and road distance, ignores stock/minimum/tax; partner self policies permit
approval changes, transition RPCs lack prior-state checks, admin views run with
owner privileges. New migration is required before release. Live schema has not
been changed. Live metadata matches the targeted contracts, but the migration
ledger has no recorded versions. Stage migrations/functions together; do not
blindly replay the existing migrations against that project.

Google Routes server secret, Supabase config, test accounts, Firebase/APNs and
signing assets are external prerequisites. Map viewport is never saved as a
location without an explicit pin. No GPS/background permissions. iOS archive
requires macOS/Xcode.
