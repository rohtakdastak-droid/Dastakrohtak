# Dastak deployment and Android

## Supabase authentication (required on the hosted project)

Authentication > URL Configuration:
- Site URL: `https://rohtak-dastak.vercel.app`
- Allowed redirect URLs: `https://rohtak-dastak.vercel.app/` and `com.dastak.app://auth/callback`
- Local development only: `http://localhost:5173/`

Enable Google under Authentication > Providers using the Google **Web** OAuth client ID and secret. The Google authorized callback URI is `https://mhkmlwxnelrwrayjwsvv.supabase.co/auth/v1/callback`. An Android OAuth client alone does not enable Supabase Google login. Native login uses an external browser and PKCE, then returns to the app.

## Routing

Both routing functions now accept `GOOGLE_MAPS_API_KEY` or `GOOGLE_ROUTES_API_KEY` in Supabase secrets. Enable Routes API and billing for that key. Do not put this server key in VITE_* variables. There is no straight-line fallback.

Run `npx supabase login` in your own terminal (do not send the token in chat), then:

```powershell
npx supabase functions deploy route-distance --project-ref mhkmlwxnelrwrayjwsvv
npx supabase functions deploy place-order --project-ref mhkmlwxnelrwrayjwsvv
```

The config disables legacy gateway JWT checking for those two functions; each function verifies the signed-in user with Supabase Auth before using Google. Deploy source and config together.

## Android artifacts

Build with JDK 21 and Android SDK 36. Run `npm run build`, `npx cap sync android`, then Gradle `assembleRelease bundleRelease`. Back up the ignored upload keystore and `android/key.properties` securely. Do not commit or share these files.

A signed APK is for direct Android installation. The signed AAB is for Play Console testing/upload; successful compilation is not Play approval or an end-to-end acceptance test. Play App Signing uses its own app-signing certificate for production OAuth fingerprints.

Outstanding verification: hosted Google configuration, real road-route checkout and payments, device OAuth, native push, Play policy/data safety/account-deletion requirements. Existing Web Push does not implement background push inside a Capacitor WebView. Native Android push needs Firebase/FCM configuration and integration.

Previously exposed Google/VAPID private keys and the predictable webhook token should be rotated. Never send private keys or access tokens in chat. Rebuild after changing public environment values and redeploy hosted frontend fixes.

## Verified in this build

- Signed release APK and AAB built with JDK 21; APK signature verified and AAB jar signature verified.
- Live Google provider reports enabled. Production Site URL and web/native redirect allowlist updated and verified by a zero-diff readback.
- route-distance and place-order deployed; missing/forged tokens return HTTP 401 (previously route-distance returned 404).
- Public Supabase configuration restored to the local build; no Google server key detected in the bundled JavaScript.
- No physical device was connected. Google routing with an authenticated user, real payments, native push, and Play approval remain unverified.
