# ApplaudIQEmbed — iOS SDK

Embed the **Applaud IQ** recognition portal inside a native iOS app. The SDK hosts the portal in a
`WKWebView` and handles the token bridge + SSO; you pass a **publishable key** (and, for auto-login, a
one-time token), present a view controller, and handle a few callbacks.

- **iOS 14+** · Swift **and** Objective-C · no third-party dependencies
- Install via **CocoaPods**, **Swift Package Manager**, or **manually**

---

## Build integration

### 1. Install

**CocoaPods** — add to your `Podfile`, then `pod install` ([cocoapods.org/pods/ApplaudIQEmbed](https://cocoapods.org/pods/ApplaudIQEmbed)):

```ruby
pod 'ApplaudIQEmbed', '~> 1.1'
```

**Swift Package Manager** — File → Add Packages… (or in `Package.swift`):

```swift
.package(url: "https://github.com/therewardstore/applaudiq-embed-ios.git", from: "1.1.0")
```

**Manual** — the SDK is pure Swift with no dependencies:

- **Source drop-in:** copy `Sources/ApplaudIQEmbed/` into your Xcode project (check _Copy items if needed_ +
  your app target). Nothing else to link.
- **Binary (`.xcframework`):** build once and embed it —
  `xcodebuild -create-xcframework -framework <device>.framework -framework <sim>.framework -output ApplaudIQEmbed.xcframework`,
  then drag it into **Target → General → Frameworks, Libraries & Embedded Content** and set **Embed & Sign**.

### 2. Import

```swift
// Swift
import ApplaudIQEmbed
```

```objc
// Objective-C
@import ApplaudIQEmbed;
```

### 3. Get your keys

- **Publishable key** (`pk_live_…` / `pk_test_…`) — from **HR portal → Settings → Embed SDK Keys**.
  Safe to ship in the app; **required in both login modes**.
- **Auto-login only:** your server mints a one-time `embedToken` (`POST <api>/api/v1/embed/sessions`
  with the server secret) — the secret never goes in the app. Manual login needs neither.

### 4. Present the embed

**Manual login** — the portal shows its own email / SSO login; just the publishable key:

```swift
// Swift
let vc = ApplaudIQEmbed.makeViewController(
    config: .init(key: "pk_live_…"),
    options: .init(mode: .manual)
)
present(vc, animated: true)
```

```objc
// Objective-C
AIQEmbedOptions *options = [AIQEmbedOptions optionsWithMode:AIQEmbedModeManual token:nil];
UIViewController *vc = [AIQEmbed makeViewControllerWithKey:@"pk_live_…" baseURL:nil options:options];
[self presentViewController:vc animated:YES completion:nil];
```

**Auto-login** — silent sign-in with a token your server minted:

```swift
// Swift
var options = ApplaudIQEmbed.Options(mode: .auto, token: embedToken)
options.onReady       = { /* signed in, feed shown */ }
options.onAuthPending = { /* signed in, awaiting HR approval */ }
options.onError       = { message in /* sign-in failed */ }
options.onClose       = { /* embed dismissed */ }

let vc = ApplaudIQEmbed.makeViewController(
    // baseURL defaults to https://recognize.applaudiq.com.
    // ssoCallback is YOUR app's scheme (also register it in Info.plist CFBundleURLSchemes) — default applaudiq://sso-callback.
    config: .init(key: "pk_live_…", ssoCallback: "myapp://sso-callback"),
    options: options
)
present(vc, animated: true)
```

```objc
// Objective-C
AIQEmbedOptions *options = [AIQEmbedOptions optionsWithMode:AIQEmbedModeAuto token:embedToken];
options.onReady       = ^{ /* signed in, feed shown */ };
options.onAuthPending = ^{ /* signed in, awaiting HR approval */ };
options.onError       = ^(NSString *message) { /* sign-in failed */ };
options.onClose       = ^{ /* embed dismissed */ };
options.onSignOut     = ^{ /* user signed out of an auto embed — tear down your session */ };

UIViewController *vc = [AIQEmbed makeViewControllerWithKey:@"pk_live_…" baseURL:nil options:options];
[self presentViewController:vc animated:YES completion:nil];
```

### 5. Handle callbacks

`onReady` (signed in & shown) · `onAuthPending` (signed in, awaiting HR approval — show a pending state) ·
`onError(message)` (bad/expired key or token, blocked load — offer a retry) · `onClose` (embed dismissed) ·
`onSignOut` (the user signed out of an **auto** / host-managed embed — tear down your app's session).

### Config options

`Config(key:baseURL:ssoCallback:backNavigation:)`:

- **`ssoCallback`** — your app's SSO deep link (`scheme://host`, default `applaudiq://sso-callback`); also register
  the scheme in your Info.plist `CFBundleURLSchemes`.
- **`backNavigation`** — default **`true`**: the WKWebView's left-edge back-swipe is enabled so the gesture steps
  back through the embed's in-app history. Set `false` to keep the platform default (no swipe):
  ```swift
  config: .init(key: "pk_live_…", backNavigation: false)
  ```

---

## Test integration

- Run on a simulator. **Manual login works with just the publishable key** — no server needed.
- For auto-login, point your app at a backend that mints a token, or test with a token minted via curl.
- A brand-new employee signs in but sees a **pending HR approval** screen until an HR admin approves them
  (`onAuthPending` fires).

## Go-live checklist

- Use a `pk_live_…` key and your production `baseURL`. **`baseURL` must be HTTPS** — a non-secure origin is
  refused at load with `onError("insecure_base_url")` (plain `http` is allowed only for `localhost` in DEBUG).
- Auto-login: a real server-side mint endpoint (never embed the `aiq_embed_…` secret in the app).
- **SSO callback scheme:** SSO runs in `ASWebAuthenticationSession` and the backend hands the one-time code back to
  your `Config.ssoCallback` deep link (sent as `native_redirect`). Use your **own** `scheme://host` (default
  `applaudiq://sso-callback`) and register the scheme in your app's **Info.plist `CFBundleURLSchemes`** — so two
  Applaud IQ apps on one device don't collide. An SSO failure (`?error=`) fires `onError(message)` and reloads the login.

---

## API

| Language        | Entry point                                                                                                                                                |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Swift**       | `ApplaudIQEmbed.makeViewController(config: .init(key:baseURL:ssoCallback:), options: .init(mode:token:))` + `onReady`/`onAuthPending`/`onError`/`onClose`/`onSignOut` on `Options` |
| **Objective-C** | `[AIQEmbed makeViewControllerWithKey:baseURL:ssoCallback:options:]` with `AIQEmbedOptions` (`AIQEmbedMode` = `Auto`/`Manual`) + the same callback blocks    |

`Mode` is `.auto` (uses `token`) or `.manual` (no token). The publishable `key` is required in both modes.

A runnable SwiftUI example lives in the
[applaudiq-sdk-example](https://github.com/therewardstore/applaudiq-sdk-example/tree/master/native-integration/ios) repo under
`native-integration/ios/`.

## Changelog

Latest: **v1.1.0 (LTS)**. See [CHANGELOG.md](./CHANGELOG.md) for the full release history (also shown on the CocoaPods / Swift Package Index page).

## License

[MIT](./LICENSE) © Applaud IQ
