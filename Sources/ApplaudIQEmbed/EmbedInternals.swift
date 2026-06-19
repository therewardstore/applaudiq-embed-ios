import Foundation

/// Pure (UIKit-free) URL + SSO logic for the embed SDK, so it can be unit-tested with `swift test`
/// (no simulator). `EmbedViewController` wires these to WKWebView / ASWebAuthenticationSession.
/// Mirrors the Android SDK's `EmbedInternals`.
enum EmbedInternals {
    /// Whitelisted SSO providers — never interpolate an arbitrary, embed-supplied value into the authorize path.
    static let ssoProviders: Set<String> = ["google", "microsoft"]

    /// `<baseURL>/embed?mode={auto|manual}&k={key}` (the page reads `mode` and the publishable `key`).
    static func embedURL(baseURL: URL, mode: String, key: String) -> URL {
        let base = baseURL.appendingPathComponent("embed")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let m = mode == "manual" ? "manual" : "auto"
        var items = [URLQueryItem(name: "mode", value: m)]
        if !key.isEmpty { items.append(URLQueryItem(name: "k", value: key)) }
        comps?.queryItems = items
        return comps?.url ?? base
    }

    /// `<baseURL>/api/v1/auth/sso/{provider}/employee/authorize?native=1[&client_id][&login_hint][&native_redirect]`.
    /// `native=1` makes the backend hand the session back as a one-time code on the app's callback deep link;
    /// `native_redirect=<scheme>://<host>` tells the backend WHICH app scheme to hand it to (so two Applaud IQ apps
    /// on one device don't collide). Provider is allowlisted (unknown → google).
    static func ssoAuthorizeURL(
        baseURL: URL,
        provider: String,
        clientID: String?,
        email: String?,
        nativeRedirect: String?
    ) -> URL? {
        let p = ssoProviders.contains(provider.lowercased()) ? provider.lowercased() : "google"
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/auth/sso/\(p)/employee/authorize"),
            resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "native", value: "1")]
        if let clientID, !clientID.isEmpty, clientID != "null" {
            items.append(URLQueryItem(name: "client_id", value: clientID))
        }
        if let email, !email.isEmpty { items.append(URLQueryItem(name: "login_hint", value: email)) }
        if let nativeRedirect, !nativeRedirect.isEmpty {
            items.append(URLQueryItem(name: "native_redirect", value: nativeRedirect))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// The scheme of a `scheme://host` callback (for ASWebAuthenticationSession's `callbackURLScheme`).
    static func scheme(ofCallback callback: String) -> String {
        let s = callback.components(separatedBy: "://").first ?? "applaudiq"
        return s.isEmpty ? "applaudiq" : s
    }

    /// The one-time `code` (success) from a returned callback URL; nil if absent/empty.
    static func parseCode(from url: URL) -> String? { queryValue(from: url, name: "code") }

    /// The `error` (failure) message from a returned callback URL; nil if absent/empty.
    static func parseError(from url: URL) -> String? { queryValue(from: url, name: "error") }

    private static func queryValue(from url: URL, name: String) -> String? {
        let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
        return (v?.isEmpty == false) ? v : nil
    }
}
