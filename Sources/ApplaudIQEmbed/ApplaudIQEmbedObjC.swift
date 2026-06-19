import UIKit

// Objective-C–compatible facade over the Swift `ApplaudIQEmbed` API.
//
// The Swift API (`enum ApplaudIQEmbed` with `Config`/`Options`/`Mode`) is not visible to
// Objective-C, so this thin `@objc` class exposes the same capability to Obj-C callers:
//
//   AIQEmbedOptions *o = [AIQEmbedOptions optionsWithMode:AIQEmbedModeAuto token:embedToken];
//   o.onReady = ^{ /* signed in */ };
//   o.onError = ^(NSString *msg) { /* failed */ };
//   UIViewController *vc = [AIQEmbed makeViewControllerWithKey:@"pk_live_…" baseURL:nil options:o];
//   [self presentViewController:vc animated:YES completion:nil];
//
// Swift callers should keep using `ApplaudIQEmbed.makeViewController(config:options:)` directly.

@objc(AIQEmbedMode)
public enum AIQEmbedMode: Int {
    case auto
    case manual
}

@objc(AIQEmbedOptions)
public final class AIQEmbedOptions: NSObject {
    @objc public var mode: AIQEmbedMode
    @objc public var token: String?
    @objc public var onReady: (() -> Void)?
    @objc public var onAuthPending: (() -> Void)?
    @objc public var onError: ((String) -> Void)?
    @objc public var onClose: (() -> Void)?
    /// Fires when the user signs out from inside an auto (host-managed) embed,
    /// so the partner app can tear the embed down. See `Options.onSignOut`.
    @objc public var onSignOut: (() -> Void)?

    @objc public init(mode: AIQEmbedMode, token: String?) {
        self.mode = mode
        self.token = token
    }

    /// Convenience for Obj-C: `[AIQEmbedOptions optionsWithMode:token:]`.
    @objc public static func options(mode: AIQEmbedMode, token: String?) -> AIQEmbedOptions {
        AIQEmbedOptions(mode: mode, token: token)
    }
}

@objc(AIQEmbed)
public final class AIQEmbed: NSObject {
    /// Build the embed view controller for Objective-C callers. `baseURL` may be nil to use
    /// the production portal default. Mirrors `ApplaudIQEmbed.makeViewController(config:options:)`.
    @objc public static func makeViewController(
        key: String,
        baseURL: URL?,
        options: AIQEmbedOptions
    ) -> UIViewController {
        makeViewController(key: key, baseURL: baseURL, ssoCallback: "applaudiq://sso-callback", options: options)
    }

    /// As above, but with a per-app SSO callback deep link (`scheme://host`). SSO hands the one-time code
    /// back to this scheme (sent as `native_redirect`); also register it in your Info.plist
    /// `CFBundleURLSchemes`. Mirrors `ApplaudIQEmbed.Config(key:baseURL:ssoCallback:)`.
    @objc public static func makeViewController(
        key: String,
        baseURL: URL?,
        ssoCallback: String,
        options: AIQEmbedOptions
    ) -> UIViewController {
        let config = baseURL.map { ApplaudIQEmbed.Config(key: key, baseURL: $0, ssoCallback: ssoCallback) }
            ?? ApplaudIQEmbed.Config(key: key, ssoCallback: ssoCallback)

        var opts = ApplaudIQEmbed.Options(
            mode: options.mode == .manual ? .manual : .auto,
            token: options.token
        )
        opts.onReady = options.onReady
        opts.onAuthPending = options.onAuthPending
        opts.onError = options.onError
        opts.onClose = options.onClose
        opts.onSignOut = options.onSignOut

        return ApplaudIQEmbed.makeViewController(config: config, options: opts)
    }
}
