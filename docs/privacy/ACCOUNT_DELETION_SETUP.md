# Account deletion: deployment notes

Deploy: `supabase functions deploy delete-account` (JWT verification stays ON). `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically to Edge Functions; the service-role key is never in the app.

## Sign in with Apple token revocation (App Store guideline 5.1.1(v))

The app signs in with a native Apple ID token (no refresh token is stored). To revoke, the function needs a fresh `authorizationCode`: the delete sheet shows an optional "Continue with Apple" button for Apple accounts, and sends the code. Set these secrets:

```
supabase secrets set APPLE_TEAM_ID=XXXXXXXXXX APPLE_KEY_ID=YYYYYYYYYY \
  APPLE_CLIENT_ID=<app bundle id> APPLE_PRIVATE_KEY="$(cat AuthKey_YYYYYYYYYY.p8)"
```

The key is created in Apple Developer, Keys, with "Sign in with Apple" enabled. If the secrets or code are missing, deletion still succeeds and the response has `apple_revoked: false`. Decide with App Review whether best-effort is acceptable; to make it mandatory, require the code for Apple accounts in the function.

## Google

`GIDSignIn.disconnect` is called on the device when a Google session can be restored. If not restorable, the user can remove access at myaccount.google.com/permissions.

## Behaviour

Order on device: cloud delete (failure keeps all local data, retry offered) then purge offline queue, wipe Core Data, UserDefaults, Keychain, then local sign-out. Retrying after a lost response is safe: a deleted user's token yields `{ok:true}`.
