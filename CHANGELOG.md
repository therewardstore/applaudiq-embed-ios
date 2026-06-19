# Changelog

All notable changes to ApplaudIQEmbed are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [1.0.5]

Per-app SSO callback scheme, `native_redirect`, and SSO failure handling (parity with the Android SDK).

- **New: `Config.ssoCallback`** (and `AIQEmbed.makeViewController(key:baseURL:ssoCallback:options:)` for Objective-C).
  The app's SSO callback deep link (`scheme://host`, default `applaudiq://sso-callback`). SSO now sends it to the
  backend as **`native_redirect`**, so each app uses its OWN scheme instead of the brand-wide `applaudiq://` — two
  Applaud IQ apps on one device won't collide on the callback. Also register the scheme in your Info.plist
  `CFBundleURLSchemes`.
- **Fix: SSO failures are now surfaced.** The callback can return `?code=` (success) **or** `?error=` (failure /
  identity mismatch). Previously an `?error=` callback was silently dropped; now the SDK fires `onError(message)` and
  reloads the portal login so the user lands on a clean retry screen.
- **New: `Config.backNavigation`** (default `true`) — enables the WKWebView left-edge back-swipe so the gesture
  steps back through the embed's in-app history. Set `false` to keep the platform default (swipe disabled).
- **Internal:** the URL-building + callback-parsing logic was extracted into a unit-tested `EmbedInternals` type
  (run via `xcodebuild test`). Also dropped the dead `env=test` query param (the portal removed test mode).

## [1.0.4]

Host-managed sign-out, reliable auto-embed detection, and SSO fixes.

- **New: `onSignOut` callback** (`Options.onSignOut`, and `AIQEmbedOptions.onSignOut` for Objective-C).
  When a user signs out from inside an **auto** (host-managed) embed, the portal posts `applaudiq:signout`;
  the SDK dismisses the embed and calls `onSignOut` so the partner app can tear down its session — matching
  the web SDK's `onSignOut`.
- **Fix: auto embeds now hide the portal's own "Sign Out".** The injected bridge shim sets
  `window.__APPLAUDIQ_EMBED__ = { mode, native: true }` on every main-frame load, so the portal reliably
  detects an auto (host-owned) embed across the `/embed → /` navigation and hides its own Sign Out button
  (the host owns logout). Previously the signal was dropped on the dashboard and the button leaked through.
- **Fix: SSO authorize URL now includes the tenant `client_id`.** Native SSO previously failed with
  `BAD_REQUEST: client_id is required` because the SDK opened
  `…/auth/sso/{provider}/employee/authorize?native=1` without the tenant id. The SDK now reads `clientId`
  (number or string) and `email` from the `applaudiq:sso-request` payload and appends `client_id` +
  `login_hint` to the authorize URL (requires the portal to send those fields — employee-portal does).
- **Hardening:** the SSO provider is validated against `["google", "microsoft"]` (unknown values fall back
  to `google`) before it's used to build the authorize path; `onError("missing_token")` fires only once even
  if `applaudiq:ready` repeats; and a prior `ASWebAuthenticationSession` is cancelled before a new one starts.

## [1.0.3]

Native feel + a navigation-confinement fix (no public API change):

- **Fix: sub-frames no longer eject to the system browser.** Navigation confinement now applies to
  the **main frame only**. Previously every non-portal navigation — including sandboxed sub-frames
  like Google reCAPTCHA, fonts, and embedded widgets — was cancelled and opened in Safari, which
  broke reCAPTCHA and gave a jarring "browser" feel. The main frame stays pinned to the portal
  origin (the actual security control); cross-origin sub-frames can't read the session or move the
  top frame, so they now load in place.
- **Native feel:** no link-preview popovers (`allowsLinkPreview = false`), no swipe back/forward
  navigation gestures, no pinch-zoom, and the long-press context menu (Open / Copy Link / Share) is
  suppressed — which also stops the authenticated session URL leaking out of the embed. A small
  injected stylesheet removes the long-press callout / tap-highlight on the portal's own content
  (form fields stay selectable). Opaque background to avoid a white flash before first paint.

## [1.0.2]

Maintenance release — **no code or API changes** (the SDK source is identical to 1.0.1).

- Republished to CocoaPods + Swift Package Manager as **1.0.2**.
- Docs: README install snippets pinned to `1.0.2`; minor formatting cleanup.

## [1.0.1]

Security hardening (no public API change):

- **HTTPS-only portal origin** — `Config.baseURL` must be `https`; a non-secure origin is refused at load
  time with `onError("insecure_base_url")`. Plain `http` is tolerated only for `localhost`/`127.0.0.1` in
  **DEBUG** builds. Keeps the one-time token and session cookies off cleartext.
- **Isolated session** — the WKWebView uses a non-persistent data store, so the embedded portal's cookies
  live in memory for this view only (nothing on disk, no bleed into other web views; gone on dismiss).
- **Navigation confinement** — only same-host secure navigations load in place; any other origin / scheme is
  cancelled and opened in the system browser, so an open-redirect or in-page link can't move the
  authenticated session (or the native bridge) onto an attacker page.
- **Bridge lockdown** — the `ReactNativeWebView` shim is injected main-frame-only, and inbound messages are
  accepted only from the main frame on the portal origin (a sub-frame can't spoof the handshake / SSO /
  close).
- **No JS injection** — the token and SSO code are passed to `callAsyncJavaScript` as bound arguments rather
  than interpolated into script source.

## [1.0.0]

- Initial public release.
- `ApplaudIQEmbed.makeViewController(config:options:)` renders the Applaud IQ portal in a `WKWebView`.
- Auto-login (server-minted `embedToken`) and manual login (portal's own email / SSO). The embed URL
  carries `?mode=auto|manual` (plus `&env=test` for `pk_test_` keys and `&k=<publishable key>`).
- Lifecycle callbacks: `onReady`, `onAuthPending`, `onError`, `onClose`. Auto-login with a `nil` token
  reports `onError` instead of hanging; `onReady` fires once (on `applaudiq:authenticated` for auto).
- Native bridge via the `window.ReactNativeWebView` shim (the portal's `postToHost` delivery path), with
  JSON-string message parsing.
- SSO via `ASWebAuthenticationSession` (callback scheme `applaudiq`): authorizes with `?native=1` and
  redeems the one-time code at `/employee/auth/sso/exchange` inside the web view.
- **Objective-C support** — `@objc AIQEmbed` / `AIQEmbedOptions` / `AIQEmbedMode` facade
  (`[AIQEmbed makeViewControllerWithKey:baseURL:options:]`) alongside the Swift API.
- Distributed via Swift Package Manager and CocoaPods. iOS 14+.
