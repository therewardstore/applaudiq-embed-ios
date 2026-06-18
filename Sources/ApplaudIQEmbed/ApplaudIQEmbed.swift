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
        let contentController = WKUserContentController()
        contentController.add(self, name: "applaudiq")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = contentController
        // Native bridge: the embedded portal's postToHost() delivers messages via
        // `window.ReactNativeWebView.postMessage(JSON.stringify(...))`, so provide that
        // shim and forward it to our WKScriptMessageHandler. A plain WKWebView is a
        // top-level context (window.parent === window) with no real parent, so the web
        // SDK's `window.parent.postMessage` path is a no-op here — the RN shim is the
        // supported native path (same as the React Native SDK).
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
            WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: embedURL()))
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

    // MARK: bridge embed → native
    func userContentController(
        _ uc: WKUserContentController, didReceive message: WKScriptMessage
    ) {
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
        let msg: [String: Any] = ["source": "applaudiq-sdk", "type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
            let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new MessageEvent('message',{data:\(json),origin:location.origin}))")
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
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // Redeem the one-time SSO code INSIDE the web view (same-origin fetch) so the
    // session cookies land in the WKWebView's own cookie store — a URLSession call
    // wouldn't share them — then reload so the authenticated portal renders.
    private func completeSSO(code: String) {
        let safe = code.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        fetch('/api/v1/employee/auth/sso/exchange', {
          method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ code: "\(safe)" })
        }).then(function(r){
          if (!r.ok) throw new Error('sso_exchange_failed');
          window.location.replace('/');
        }).catch(function(){
          try { window.webkit.messageHandlers.applaudiq.postMessage(JSON.stringify(
            { source: 'applaudiq-embed', type: 'applaudiq:error', payload: { message: 'sso_exchange_failed' } })); } catch(e){}
        });
        """
        webView.evaluateJavaScript(js)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
