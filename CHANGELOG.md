# Changelog

All notable changes to ApplaudIQEmbed are documented here. This project follows
[Semantic Versioning](https://semver.org/).

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
