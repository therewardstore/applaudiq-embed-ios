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
        let config = baseURL.map { ApplaudIQEmbed.Config(key: key, baseURL: $0) }
            ?? ApplaudIQEmbed.Config(key: key)

        var opts = ApplaudIQEmbed.Options(
            mode: options.mode == .manual ? .manual : .auto,
            token: options.token
        )
        opts.onReady = options.onReady
        opts.onAuthPending = options.onAuthPending
        opts.onError = options.onError
        opts.onClose = options.onClose

        return ApplaudIQEmbed.makeViewController(config: config, options: opts)
    }
}
