# Testing ApplaudIQEmbed

A repeatable end-to-end checklist for the iOS SDK, run against the **example app**
([applaudiq-sdk-example/native-integration/ios](https://github.com/therewardstore/applaudiq-sdk-example))
pointed at a local Applaud IQ stack. The example builds the SDK from the local `:path` (CocoaPods)
so SDK edits are picked up by a `pod install` + rebuild.

## Prerequisites

- A running portal + API gateway (the loyaltyz stack): employee-portal on `:3017`, api-gateway on `:8000`.
- An embed-enabled client with **both login modes on** and an **active embed key** (publishable `pk_…` + a
  server secret `aiq_embed_…`). The demo client is `100001`, key `pk_live_…`, secret `aiq_embed_demo_e2e`.
- Local dev cookie override so WebKit keeps the embed session over `http://localhost`
  (`SameSite=Lax; Secure=false` — WebKit drops `Secure` cookies over http, unlike Chrome).
- Example `Shared/Config.swift` pointed at the local stack:
  - `BASE_URL = http://localhost:3017`
  - `PUBLISHABLE_KEY = <demo pk_…>`
  - `DEMO_EMAIL = <an approved employee>`
  - `TEST_EMBED_SECRET` comes from the scheme/`SIMCTL_CHILD_APPLAUDIQ_SECRET` env var — **never** hardcode the
    secret in the app. Revert these test values before publishing.

### Build & launch (CocoaPods variant)

```bash
cd native-integration/ios/cocoapods
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install            # picks up the local SDK version
xcodebuild -workspace ApplaudIQiOSExample.xcworkspace -scheme ApplaudIQiOSExample \
  -destination 'id=<SIMULATOR_UDID>' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <SIMULATOR_UDID> ./DerivedData/Build/Products/Debug-iphonesimulator/ApplaudIQiOSExample.app
SIMCTL_CHILD_APPLAUDIQ_SECRET=aiq_embed_demo_e2e \
  xcrun simctl launch <SIMULATOR_UDID> com.applaudiq.example.iosexample
```

Cross-check each case against the gateway request log
(filter `/api/v1/embed|auth/sso|employee/auth`).

## Matrix

### A. Publishable key

- [ ] **A1** Wrong / empty `PUBLISHABLE_KEY` → the portal renders the **"This Applaud IQ embed isn't set up"**
      info screen (host-agnostic; the portal validates `?k=` via `GET /api/v1/embed/validate` and renders the
      screen itself — no SDK change needed).
- [ ] **A2** Valid key → proceeds (manual login or auto handshake).
- [ ] **A3** `Options(mode: .auto, token: nil)` → `onError("missing_token")`, nothing hangs.
- [ ] **A4** Insecure `http://` non-localhost `baseURL` → `onError("insecure_base_url")`, nothing loads
      (localhost is allowed in DEBUG for local testing).

### B. Manual login

- [ ] **B1** Valid key, `mode: .manual` → the portal's **own** login renders inline in the WKWebView
      (email / passwordless / SSO). **No reCAPTCHA box** (native embeds skip it via an embed nonce), and it
      renders in place — **not** a Safari sheet.
- [ ] **B2** Complete email/OTP → signed-in feed; the session cookie persists across the `/login → /` hop.
- [ ] **B3** In a manual embed the dashboard user menu **still shows "Sign Out"** (the portal owns the session,
      not the host) — the inverse of C3.

### C. Auto login

- [ ] **C1** Approved employee → silent sign-in → recognition feed. `onReady` fires.
      Gateway trace: `POST /embed/sessions 200` (the host mint, UA `ApplaudIQiOSExample/…`) →
      `GET /embed/validate 200` + `POST /employee/auth/embed/exchange 200` (the WKWebView, UA `iPhone`).
- [ ] **C2** Fresh email (`autoProvision: true`) → **"Pending HR approval"**; `onAuthPending` fires.
- [ ] **C3** **Sign Out hidden in auto.** Open the dashboard user menu → the menu ends at **Settings**, with
      **no Sign Out** (the host minted the session and owns logout). Backed by the SDK injecting
      `window.__APPLAUDIQ_EMBED__ = { mode: "auto", native: true }` on every main-frame load, which the portal
      reads (`isAutoEmbed()`), surviving the `/embed → /` navigation.

### D. SSO (manual → external IdP)

- [ ] **D1** Manual login on an **SSO-configured** org → tap **Continue with Google/Microsoft** → the SDK opens
      an **`ASWebAuthenticationSession`** system-browser sheet to
      `…/api/v1/auth/sso/{provider}/employee/authorize?native=1` (Google blocks OAuth inside a WebView, so the
      system browser is required). The portal triggers this by posting `applaudiq:sso-request` when embedded.
- [ ] **D2** Cancel the sheet → returns to the login cleanly, no crash.
- [ ] **D3** (documented) Full leg: backend deep-links `applaudiq://sso-callback?code=…` → the sheet captures it
      → SDK `completeSSO` POSTs `/employee/auth/sso/exchange {code}` **inside** the WKWebView (cookie lands
      there) → feed. Completing Google needs the OAuth app to allow the `applaudiq://` native redirect + a real
      account; the code→exchange→feed leg is also covered by the backend `native_sso_callback` test.

      > Note: D requires an org with an SSO provider configured (`admin.client_sso_configs`) **and** a real
      > Google OAuth client id. A vanilla demo client with no SSO config shows email/OTP only and never renders
      > the provider buttons.

### E. Callbacks

- [ ] **E1** `onReady` (signed in & rendered), `onAuthPending` (pending HR), `onError(message)` (bad key/token),
      `onClose` (`applaudiq:close` → `dismiss` + `onClose`), `onSignOut` (`applaudiq:signout` from a
      host-managed auto sign-out → `dismiss` + `onSignOut`). Surface each on the example status line.

### F. Native feel / security

- [ ] **F1** No long-press context menu / link-preview popover, no pinch-zoom, no swipe back/forward.
- [ ] **F2** An external link opens in the system browser; the authenticated session is not moved out of the
      embed.
- [ ] **F3** Navigation confinement is **main-frame only** — the top frame stays pinned to the portal origin,
      but sandboxed sub-frames (reCAPTCHA, fonts, widgets) load in place rather than ejecting to Safari.

## Backend API matrix

The platform repo ships `scripts/tests/embed/embed-api-matrix.sh` — a curl-driven matrix covering mint /
validate / exchange / single-use / TTL / HR-approval gate / per-credential rotation / publishable-key
validation. Run it green before device testing; it exercises the server side of A/C/D independently of the
device.
