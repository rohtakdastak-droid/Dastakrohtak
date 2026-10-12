# Dastak

Multi-vendor delivery platform — customer app, admin dashboard, restaurant panel, delivery partner panel.

**This repository is Milestone 1 of a multi-milestone build.** It contains a working customer PWA, the complete Supabase schema, row-level security, server-authoritative order and payment flows, and the exact delivery-fee engine from the spec. The admin dashboard, restaurant panel, and delivery partner panel are planned as follow-up milestones that build on the same database.

## What's working now

### Database (Supabase, Postgres)
- Full relational schema in `supabase/migrations/0001_init.sql` — profiles, vendors, products, orders, order items, status history, delivery assignments, delivery earnings, payments, refunds, reviews, notifications, support tickets, app settings, admin audit log.
- Monetary values stored as integer paise. No floats for currency.
- Server-authoritative RPCs in `supabase/migrations/0002_functions.sql`:
  - `calc_delivery_fee_paise(distance_km)` — the exact rate table from the spec, including the ₹90 + ₹5/km overflow rule beyond 9 km.
  - `create_order(...)` — recomputes subtotal from live product prices, enforces single-vendor cart, snapshots prices, calculates fee, inserts order + items atomically.
  - `submit_payment_proof(...)`, `verify_payment(...)` — the manual-verification payment flow.
  - `vendor_set_order_status(...)`, `accept_delivery(...)`, `partner_set_order_status(...)` — role-restricted state transitions.
  - `accept_delivery` is race-safe: a partial unique index on `delivery_assignments(order_id) where status='accepted'` guarantees exactly one winner.
- Row-level security on every table in `supabase/migrations/0003_rls.sql`. Customers see only their own data; vendors see only their vendor's data; delivery partners see only their assignments and earnings; admins see everything.
- Auto profile creation on signup via trigger.

### Customer PWA (`src/`)
- React + TypeScript + Vite + Tailwind, installable as a PWA.
- Email magic-link auth via Supabase.
- Home: four categories (food, medicine, accessories, groceries), search, Pure-Veg toggle, vendor list sorted by admin priority.
- Vendor page: menu with veg/non-veg indicators, add/update/remove, single-vendor-cart switch dialog.
- Checkout: live delivery-fee calculation (mirrored client-side; server is authoritative), haversine fallback with provider recorded.
- Order detail: live realtime status via Supabase channels, UPI deep-link, UPI reference submission, explicit note that a screenshot does not confirm payment.
- Theme: light / dark / system, persisted.
- Order history list.

### Admin dashboard (`src/admin/`)
- `/admin` desktop-first layout with sidebar, mobile-friendly top bar.
- **Overview**: today's orders / awaiting payment / preparing / in delivery / delivered / cancelled, verified collections, gross order value, top vendors, recent orders, platform counts. Live via Supabase realtime.
- **Restaurants**: create / edit / delete vendors, enable-disable, featured toggle, up/down reorder (persisted via `admin_reorder_vendors` RPC).
- **Products**: per-vendor product CRUD, diet classification, enable-disable, sale pricing.
- **Orders**: filtered + searchable list, cancel-with-reason via `admin_cancel_order` RPC, realtime updates.
- **Payments**: ledger with Submitted / Verified / Rejected tabs, approve/reject using `verify_payment` RPC, CSV export.
- **Delivery Partners**: assign delivery role by display name, approve / suspend / reactivate using `admin_set_partner_status`, see QR code, online status.
- **Settings**: edit UPI VPA / payee name / QR image path / instructions, COD toggle (OFF by default), verification mode selector, full editable delivery-rate table with overflow rule (atomic save via `admin_replace_rate_table`), tax percent.
- **Audit log**: last 200 admin actions with actor, action, entity, reason, timestamp.

### Restaurant partner panel (`src/vendor/`)
- `/vendor` desktop sidebar + mobile top bar, auto-detects which vendors the signed-in user is a member of (vendor_members).
- **Dashboard**: today's orders, new (awaiting your acceptance), preparing, delivered, cancelled, verified collections, rating. Live via realtime.
- **Orders**: tabbed by state (New / Preparing / Ready / In delivery / Delivered / Cancelled). Accept, reject-with-reason, mark ready — all via the role-restricted `vendor_set_order_status` RPC.
- **Order detail**: items snapshot, delivery destination, status history, action buttons.
- **Menu**: add / edit / delete / enable items (only for this vendor; RLS enforces).
- **Profile**: edit description, dispatch address + coordinates, prep time, min order, service radius. Admin keeps control of name, category, images, status.

### Notifications (all roles)
- `supabase/migrations/0005_vendor_notifications.sql` fans out notifications to every active vendor member on new orders and payment-verified orders, and notifies partners on accepted assignments. Combined with the existing per-user notifications, this delivers to customers, vendors, delivery partners, and admins.
- `src/components/NotificationBell.tsx` — shared bell with unread badge, dropdown, "mark all read", and browser-level `Notification` toast when the tab is open. Mounted on the customer home, admin dashboard, and vendor panel.
- Realtime subscription filters per `user_id` so each person only receives their own notifications.

### Sign in with Google (free)
- `signInWithGoogle()` in `src/lib/auth.ts` uses Supabase's built-in Google OAuth.
- Enable in your Supabase project: **Authentication → Providers → Google** → add your Google Cloud OAuth client ID & secret (both are free). Add your deployed origin (and `http://localhost:5173`) to the Google OAuth "Authorized redirect URIs" as:
  `https://<your-project>.supabase.co/auth/v1/callback`
- Once enabled, the "Continue with Google" button on the login screen signs the user in. A profile row is auto-created by the signup trigger.

### Delivery partner app (`src/partner/`)
- `/partner` — mobile-first bottom-tab layout. Guarded by `role=delivery`. Pending accounts can set up profile but can't accept orders until an admin approves them.
- **Available**: online/offline toggle, live list of orders in `ready_for_pickup` with no accepted assignment. Pulls from `list_available_orders` RPC. Realtime refresh when orders or assignments change.
- **Accept flow**: atomic — calls `accept_delivery` RPC. If another partner wins first, the DB unique partial index raises `order already assigned` and the UI refreshes.
- **Active**: shows pickup + drop with Google-Maps-navigation deep-links, item count, customer note, order value and partner earning. Workflow: Arrived at pickup → Confirm pickup → Start delivery → Mark delivered. Each transition goes through `partner_set_order_status` (role-restricted in SQL).
- **Earnings**: today / week / month counts + totals, pending vs settled, per-order history. Pulled from `my_earnings_summary` RPC + `delivery_earnings` table (RLS limits to self).
- **Profile**: status, approval date, vehicle details, partner QR code (does not contain any identity document), and a document-submission form that stores only a masked reference (last 4 digits) — never the full ID — for admin review.
- SQL additions in [supabase/migrations/0006_delivery.sql](supabase/migrations/0006_delivery.sql): `list_available_orders`, `my_active_delivery`, `my_earnings_summary`, `set_partner_online`.

### Real road-routing (Google Maps Routes API)
- Supabase Edge Functions in `supabase/functions/`:
  - `route-distance` — called from Checkout to preview the live road distance so the fee updates as the user picks their address.
  - `place-order` — the server-authoritative order placer. It reads the vendor's dispatch coordinates **from the DB** (not from the client), re-queries Google Routes server-side, enforces service-radius, and then calls `create_order` with the trusted distance and `route_provider='google'`. A tampered client cannot inject a shorter distance to lower the fee.
- Haversine is no longer used at checkout. If Google routing is unconfigured or fails, the order is refused with a retry message — matching the spec's rule that we must never use an invented distance.
- Setup:
  1. In Google Cloud, create a project, enable the **Routes API**, create an API key, restrict it to the Routes API.
  2. Store the key as a Supabase secret (never in the frontend):
     ```bash
     supabase secrets set GOOGLE_MAPS_API_KEY=AIza...
     ```
  3. Deploy both functions:
     ```bash
     supabase functions deploy route-distance
     supabase functions deploy place-order
     ```
  4. In the Supabase dashboard → Edge Functions, both functions should be `active`. Billing-wise Google gives $200 of free Maps credits per month — enough for thousands of calls at Routes API v2 pricing.

### Web Push notifications
- Pure VAPID Web Push — no Firebase account needed. Works on Chrome, Edge, Firefox, and Android (iOS Safari 16.4+).
- `supabase/migrations/0007_push.sql` — `push_subscriptions` table with RLS, and a DB trigger (`trg_notification_push`) that fires on every notification INSERT. The trigger calls the `send-push` Edge Function via `pg_net`.
- `supabase/functions/send-push/index.ts` — Receives the notification payload, reads push subscriptions for that user, encrypts each payload per RFC 8291, and sends to push services with VAPID auth. Stale endpoints (410/404) are auto-cleaned.
- `src/sw.ts` — Custom service worker (injectManifest via vite-plugin-pwa) with `push` and `notificationclick` handlers. Clicking a notification opens or focuses the relevant order page.
- `src/lib/push.ts` — Client helpers: `subscribePush()` registers the device and upserts the subscription to Supabase; `unsubscribePush()` cleans up.
- `NotificationBell` auto-subscribes when permission is already granted, and shows an "Enable push" button otherwise.
- Setup:
  1. Generate VAPID keys:
     ```bash
     npx web-push generate-vapid-keys
     ```
  2. Store secrets on Supabase:
     ```bash
     supabase secrets set VAPID_PUBLIC_KEY=BPxx... VAPID_PRIVATE_KEY=abc... VAPID_SUBJECT=mailto:you@example.com PUSH_WEBHOOK_TOKEN=some-long-random-string
     ```
  3. Configure the DB webhook URL (SQL editor):
     ```sql
     alter database postgres set "app.push_webhook_url"   to 'https://<ref>.functions.supabase.co/send-push';
     alter database postgres set "app.push_webhook_token" to 'some-long-random-string';
     ```
  4. Add the public key to `.env.local`:
     ```
     VITE_VAPID_PUBLIC_KEY=BPxx...
     ```
  5. Deploy:
     ```bash
     supabase functions deploy send-push
     ```

## What is NOT built yet

- Payment gateway integration. Only manual UPI-QR verification is wired.
- Image/file uploads for product photos, QR image, delivery-partner documents (bucket wiring).
- Automated tests.
- Ratings & reviews UI (DB + RLS are ready).
- Support tickets UI (DB + RLS are ready).

## Setup

### 1. Supabase project
1. Create a Supabase project at https://supabase.com.
2. In the SQL editor, run in order:
   - `supabase/migrations/0001_init.sql`
   - `supabase/migrations/0002_functions.sql`
   - `supabase/migrations/0003_rls.sql`
   - `supabase/migrations/0004_admin.sql`
   - `supabase/migrations/0005_vendor_notifications.sql`
   - `supabase/migrations/0006_delivery.sql`
   - `supabase/migrations/0007_push.sql`
   - `supabase/seed.sql` (optional, dev data)
3. Create a Storage bucket `payment-qr` (public read) for the admin UPI QR image. Create private buckets `partner-docs` and `payment-proofs` for sensitive files.
4. After you sign in once, promote yourself to admin by running in the SQL editor:
   ```sql
   update profiles set role = 'admin' where id = (
     select id from auth.users where email = 'you@example.com'
   );
   ```

### 2. Frontend
```bash
cp .env.example .env.local
# fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```
The app serves at `http://localhost:5173`.

### 3. Build
```bash
npm run build
npm run preview
```

## Delivery fee verification

The schedule in `delivery_rate_rules` and the overflow rule in `delivery_overflow_rule` match the spec exactly:

| Distance | Fee |
|---|---|
| 0–1 km | ₹15 |
| 1.5 km | ₹20 |
| 3 km | ₹33 |
| 5 km | ₹55 |
| 8 km | ₹83 |
| 9 km | ₹90 |
| 9.1 km | ₹95 |
| 10 km | ₹95 |
| 11 km | ₹100 |

Verify in SQL:
```sql
select d, calc_delivery_fee_paise(d) / 100.0 as rupees
from unnest(array[0.5, 1.0, 1.5, 3.0, 5.0, 8.0, 9.0, 9.1, 10.0, 11.0, 20.0]) as d;
```

## Security notes

- The anon key in `.env.local` is safe for the browser; RLS enforces access.
- The service-role key must NEVER be exposed to the frontend. Use it only in Edge Functions.
- Payment proofs and partner documents belong in private buckets with short-lived signed URLs for admin review.
- `create_order` is `security definer` and ignores any price supplied by the client — it reads prices from the `products` table.

## Attribution

Spec: see `MASTER_PROMPT` in the issue tracker / original brief.
