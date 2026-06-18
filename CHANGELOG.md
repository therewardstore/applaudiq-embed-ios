# Changelog

All notable changes to ApplaudIQEmbed are documented here. This project follows
[Semantic Versioning](https://semver.org/).

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
