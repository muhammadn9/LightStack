# Auth Email Fix Plan

## Root cause
Supabase Auth (project tzyjfgcasifincmfnerj) uses custom SMTP via Resend with a sender on lightstack.org. The domain lapsed, so Resend rejects sends (550) and signup-confirm / password-reset emails fail.
Status: NOT confirmed from logs. The Supabase auth_logs query returned no SMTP/550 errors in the last 24h (only token refreshes), so no email attempt was logged in that window. The SMTP settings themselves are not readable via MCP; the owner should confirm in Dashboard > Auth > SMTP and Resend > Domains/Logs.

## Options (ranked)
1. **Owner action: new domain verified in Resend (recommended, permanent).**
   - Buy any cheap domain (or renew lightstack.org, simplest: no config change except DNS if registrar kept records).
   - Resend > Domains > Add Domain > add the DNS records Resend shows: SPF (TXT on `send` subdomain, `v=spf1 include:amazonses.com ~all`), DKIM (TXT `resend._domainkey`), MX on `send` subdomain; optionally DMARC TXT `_dmarc`. Wait for "Verified".
   - Supabase Dashboard > Authentication > Emails > SMTP Settings: Host `smtp.resend.com`, Port 465, Username `resend`, Password = Resend API key (sending access), Sender email `noreply@<new-domain>`, Sender name `LightStack`.
   - If domain changed, no app code change (links use lightstack://, not the domain). Test with reset email.
2. **Owner action: temporarily disable custom SMTP (built-in Supabase SMTP).** Dashboard > Auth > SMTP > turn off. Per Supabase docs it only delivers to addresses that are members of the project's organization team (others fail "Email address not authorized") and is heavily rate limited, not for production. Fine only for the owner/testers added as team members.
3. **Owner action: disable "Confirm email"** (Auth > Providers > Email) and rely on Google/Apple sign-in. Fixes signup immediately, but password reset still needs email, and unverified emails allow fake accounts. Use only as a stopgap. Note: app's EmailVerificationView flow expects a no-session signup; with confirm off, signUp returns a session and the app must handle it (code change, see below).
4. **Other free providers without a domain:** none reliable. Resend's shared `onboarding@resend.dev` sender can only deliver to the Resend account owner's own email. Brevo/Mailgun/SendGrid free tiers require a verified sender; Brevo allows verifying a single sender email (e.g. a Gmail address) via confirmation link, but Gmail-from via third-party SMTP often lands in spam (DMARC). Acceptable for testing only.

## App-side findings (code changes, none made)
- Redirect URL `lightstack://auth-callback` (AuthService.redirectURL) matches Info.plist scheme `lightstack`. Owner action: confirm it is in Dashboard > Auth > URL Configuration > Redirect URLs (and Site URL is not a dead lightstack.org page).
- **Gap:** password-reset link goes through handleDeepLink -> `auth.session(from:)`, which signs the user in, but there is no recovery UI (no `passwordRecovery` event handling / `auth.update(user: password)` anywhere). Users can sign in via the link yet never set a new password. Needs a "Set new password" screen. Code change.
- Signup errors surface via notifyError, but `resendVerificationEmail` swallows failures (only logs). Code change: show an error when resend fails, and map SMTP failures (HTTP 500 / "Error sending ... email") to a friendly message in signUp, like `resetPasswordMessage` already does for reset.
- If option 3 is used: handle `.session` response from signUp (skip verification screen).
- Edge Functions: only `ai-proxy`; no email-sending functions. No supabase/config.toml or email templates in repo (templates live in the dashboard).
