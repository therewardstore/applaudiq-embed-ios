import AuthenticationServices
import UIKit
import WebKit

/// ApplaudIQEmbed — renders the full Applaud IQ recognition portal in a
/// WKWebView with auto-login. Mirrors the web SDK's bridge protocol.
///
/// Auto-login: your BACKEND mints a one-time `embedToken`
/// (POST /api/v1/embed/sessions with the secret key); pass it here.
///
///   let vc = ApplaudIQEmbed.makeViewController(
///       config: .init(key: "pk_live_xxx"),
///       options: .init(mode: .auto, token: embedToken))
///   present(vc, animated: true)
///
/// SSO can't run inside a WKWebView (Google/Microsoft block embedded webviews),
/// so an SSO request opens ASWebAuthenticationSession (system browser) and the
/// returned one-time code is relayed back into the web view.
public enum ApplaudIQEmbed {
    public struct Config {
        public let key: String
        /// The portal origin. Must be HTTPS (http is accepted only for localhost in DEBUG); a
        /// non-secure origin is refused at load time and surfaces `onError("insecure_base_url")`.
        public let baseURL: URL
        public init(key: String, baseURL: URL = URL(string: "https://recognize.applaudiq.com")!) {
            self.key = key
            self.baseURL = baseURL
        }
    }

    public enum Mode: String { case auto, manual }

    public struct Options {
        public let mode: Mode
        public let token: String?
        public var onReady: (() -> Void)?
        public var onClose: (() -> Void)?
        public var onError: ((String) -> Void)?
        public var onAuthPending: (() -> Void)?
        public init(mode: Mode = .auto, token: String? = nil) {
            self.mode = mode
            self.token = token
        }
    }

    public static func makeViewController(config: Config, options: Options) -> UIViewController {
        EmbedViewController(config: config, options: options)
    }
}

final class EmbedViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate,
    ASWebAuthenticationPresentationContextProviding
{
    private let config: ApplaudIQEmbed.Config
    private let options: ApplaudIQEmbed.Options
    private var webView: WKWebView!
    private var authSession: ASWebAuthenticationSession?
    private var tokenSent = false
    private var readyFired = false

    init(config: ApplaudIQEmbed.Config, options: ApplaudIQEmbed.Options) {
        self.config = config
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Refuse an insecure portal origin: the one-time token and the session cookies must
        // never travel over cleartext. HTTPS is required; plain http is tolerated only for a
        // localhost dev portal in DEBUG builds. (On web the browser/CSP enforce this; on iOS
        // we must.)
        guard isPortalURL(config.baseURL) else {
            options.onError?("insecure_base_url")
            return
        }

        let contentController = WKUserContentController()
        contentController.add(self, name: "applaudiq")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = contentController
        // Isolate the embedded session: a non-persistent store keeps the portal's cookies in
        // memory for this view only — nothing lands on disk or bleeds into other app web views,
        // and the session is gone when the embed is dismissed. Auto-login mints a fresh token
        // each open and manual re-authenticates, so persistence would buy nothing and cost
        // isolation.
        cfg.websiteDataStore = .nonPersistent()
        // Native bridge: the embedded portal's postToHost() delivers messages via
        // `window.ReactNativeWebView.postMessage(JSON.stringify(...))`, so provide that
        // shim and forward it to our WKScriptMessageHandler. A plain WKWebView is a
        // top-level context (window.parent === window) with no real parent, so the web
        // SDK's `window.parent.postMessage` path is a no-op here — the RN shim is the
        // supported native path (same as the React Native SDK). Main frame only: a sub-frame
        // the portal might load must not be handed a native bridge.
        let bridge = """
        (function(){
          window.ReactNativeWebView = window.ReactNativeWebView || {
            postMessage: function(s){
              try { window.webkit.messageHandlers.applaudiq.postMessage(s); } catch(e){}
            }
          };
        })();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: embedURL()))
    }

    /// True when `url` is the trusted portal origin we may load and stay on: the same host as the
    /// configured `baseURL`, over HTTPS (or http://localhost in DEBUG for a dev portal).
    private func isPortalURL(_ url: URL) -> Bool {
        guard let host = url.host, host == config.baseURL.host else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
        if url.scheme == "http", host == "localhost" || host == "127.0.0.1" { return true }
        #endif
        return false
    }

    /// Build `<baseURL>/embed?mode=…[&env=test]&k=…` — the page reads `mode` (auto vs
    /// manual → portal login), `env` (the "Test mode" pill), and `k` (the publishable
    /// key, used server-side for the frame-ancestors allowlist on web).
    private func embedURL() -> URL {
        let base = config.baseURL.appendingPathComponent("embed")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "mode", value: options.mode.rawValue)]
        if config.key.hasPrefix("pk_test_") { items.append(URLQueryItem(name: "env", value: "test")) }
        if !config.key.isEmpty { items.append(URLQueryItem(name: "k", value: config.key)) }
        comps?.queryItems = items
        return comps?.url ?? base
    }

    // MARK: navigation confinement (WKNavigationDelegate)
    // A native web view has no frame-ancestors CSP, so we pin it to the portal origin ourselves:
    // only same-host secure navigations load in place; everything else (other origins, custom
    // schemes, http) is cancelled and handed to the system browser. This stops an open redirect
    // or an in-page link from moving the authenticated session — and the native message bridge —
    // onto an attacker-controlled page.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "about" || isPortalURL(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.scheme == "https" || url.scheme == "http" {
            UIApplication.shared.open(url)
        }
    }

    // MARK: bridge embed → native
    func userContentController(
        _ uc: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        // Only the main frame, served from the portal origin, may drive the native bridge — a
        // sub-frame (embedded third-party content) or a navigated-away page must not be able to
        // spoof the handshake or trigger SSO / close.
        guard message.frameInfo.isMainFrame,
            message.frameInfo.securityOrigin.host == config.baseURL.host
        else { return }

        // postToHost() sends a JSON string (via the ReactNativeWebView shim); parse it.
        // Fall back to a dictionary body in case a host delivers an object directly.
        let body: [String: Any]?
        if let str = message.body as? String, let data = str.data(using: .utf8) {
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else {
            body = message.body as? [String: Any]
        }
        guard let body, let type = body["type"] as? String,
            (body["source"] as? String) == "applaudiq-embed"
        else { return }

        switch type {
        case "applaudiq:ready":
            if options.mode == .auto {
                if let token = options.token, !tokenSent {
                    tokenSent = true
                    sendToEmbed("applaudiq:init-token", ["token": token])
                } else if options.token == nil {
                    // Auto with no token can never sign in — tell the embed to stop
                    // spinning (show its error screen) and surface it to the host.
                    sendToEmbed("applaudiq:init-error", [:])
                    options.onError?("missing_token")
                }
            } else {
                // Manual: the mount handshake is the only "ready" we get before the
                // page hands off to the portal's own login.
                fireReady()
            }
        case "applaudiq:authenticated": fireReady()  // auto: the definitive signed-in signal
        case "applaudiq:auth-pending": options.onAuthPending?()
        case "applaudiq:error":
            options.onError?(((body["payload"] as? [String: Any])?["message"] as? String) ?? "error")
        case "applaudiq:close": dismiss(animated: true) { self.options.onClose?() }
        case "applaudiq:sso-request":
            let provider = (body["payload"] as? [String: Any])?["provider"] as? String ?? "google"
            startSSO(provider: provider)
        default: break
        }
    }

    private func fireReady() {
        guard !readyFired else { return }
        readyFired = true
        options.onReady?()
    }

    private func sendToEmbed(_ type: String, _ payload: [String: Any]) {
        // Pass the message as a bound `arguments` value rather than interpolating JSON into JS
        // source, so the token can never break out of (or inject into) the evaluated script.
        let msg: [String: Any] = ["source": "applaudiq-sdk", "type": type, "payload": payload]
        webView.callAsyncJavaScript(
            "window.dispatchEvent(new MessageEvent('message', { data: msg, origin: location.origin }));",
            arguments: ["msg": msg],
            in: nil,
            in: .page,
            completionHandler: nil)
    }

    // MARK: SSO via system browser
    // Google/Microsoft block embedded webviews, so SSO runs in ASWebAuthenticationSession.
    // `native=1` makes the backend hand the session back as a one-time code on the
    // `applaudiq://sso-callback` deep link (instead of a web cookie redirect).
    private func startSSO(provider: String) {
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api/v1/auth/sso/\(provider)/employee/authorize"),
            resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "native", value: "1")]
        guard let url = comps?.url else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "applaudiq") {
            [weak self] callbackURL, _ in
            guard let self, let cb = callbackURL,
                let code = URLComponents(url: cb, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            self.completeSSO(code: code)
        }
        session.presentationContextProvider = self
        // Non-ephemeral: reuse the system browser's existing IdP session for one-tap SSO. The
        // trade-off is the SSO identity persists in Safari beyond the app — flip to true to force
        // a fresh, isolated sign-in each time.
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // Redeem the one-time SSO code INSIDE the web view (same-origin fetch) so the
    // session cookies land in the WKWebView's own cookie store — a URLSession call
    // wouldn't share them — then reload so the authenticated portal renders.
    private func completeSSO(code: String) {
        // The code is passed as a bound `arguments` value (not interpolated into the script), so
        // it can't inject into the evaluated JS. callAsyncJavaScript surfaces a failed exchange
        // as a thrown error → `.failure`, which we relay to the host directly.
        let js = """
        const r = await fetch('/api/v1/employee/auth/sso/exchange', {
          method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ code: code })
        });
        if (!r.ok) throw new Error('sso_exchange_failed');
        window.location.replace('/');
        """
        webView.callAsyncJavaScript(js, arguments: ["code": code], in: nil, in: .page) {
            [weak self] result in
            if case .failure = result { self?.options.onError?("sso_exchange_failed") }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
