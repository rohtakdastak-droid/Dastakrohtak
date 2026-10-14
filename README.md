# Dastak – Local Delivery

Multi-restaurant food ordering and delivery for Rohtak: customers, restaurants/cafes, delivery partners and admins in one Android app.

| Folder | What it is |
|---|---|
| `mobile/` | Flutter Android app (all four panels). Build and test instructions: `mobile/README.md`. |
| `supabase/` | Database migrations and Edge Functions (`place-order`, `send-push`, `signup-customer`). |
| `public/`, `index.html` | Public website on Vercel: landing page, `privacy.html`, `delete-account.html`. |

## Website

```bash
npm install
npm run build
```

Vercel deploys `dist/` from `main`. `public/sw.js` deliberately unregisters the old web app's offline service worker.

## Important

- Build the app with `--dart-define-from-file=config/local.json`, otherwise it opens on the setup screen.
- The live database migration ledger is empty: never run `supabase db push`. Apply reviewed SQL with `supabase db query --linked -f <file>` after approval. Test first with `cd mobile/tools && npm test`.
- Signing keys live only in the git-ignored `release-artifacts/` folder. Back them up; losing them blocks Play Store updates.
