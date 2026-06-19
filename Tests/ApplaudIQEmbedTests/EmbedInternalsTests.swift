import XCTest

@testable import ApplaudIQEmbed

/// Pure-logic unit tests for the embed SDK URL/SSO building + callback parsing (parity with the
/// Android SDK's EmbedInternalsTest). iOS-only package → run via `xcodebuild test` on a simulator.
final class EmbedInternalsTests: XCTestCase {
    private let portal = URL(string: "https://recognize.applaudiq.com")!

    private func query(_ url: URL?, _ name: String) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    // MARK: embedURL
    func testEmbedURL_auto() {
        let u = EmbedInternals.embedURL(baseURL: portal, mode: "auto", key: "pk_live_x")
        XCTAssertTrue(u.absoluteString.hasPrefix("https://recognize.applaudiq.com/embed?"))
        XCTAssertEqual(query(u, "mode"), "auto")
        XCTAssertEqual(query(u, "k"), "pk_live_x")
    }

    func testEmbedURL_manual() {
        let u = EmbedInternals.embedURL(baseURL: portal, mode: "manual", key: "pk_live_x")
        XCTAssertEqual(query(u, "mode"), "manual")
    }

    func testEmbedURL_unknownModeFallsBackToAuto() {
        let u = EmbedInternals.embedURL(baseURL: portal, mode: "bogus", key: "pk_live_x")
        XCTAssertEqual(query(u, "mode"), "auto")
    }

    // MARK: ssoAuthorizeURL
    func testSsoURL_native1WithClientHintAndRedirect() {
        let u = EmbedInternals.ssoAuthorizeURL(
            baseURL: portal, provider: "google", clientID: "100001", email: "a@b.com",
            nativeRedirect: "aiqexample://sso-callback")
        XCTAssertTrue(u!.absoluteString.contains("/api/v1/auth/sso/google/employee/authorize"))
        XCTAssertEqual(query(u, "native"), "1")
        XCTAssertEqual(query(u, "client_id"), "100001")
        XCTAssertEqual(query(u, "login_hint"), "a@b.com")
        XCTAssertEqual(query(u, "native_redirect"), "aiqexample://sso-callback")
    }

    func testSsoURL_unknownProviderFallsBackToGoogle() {
        let u = EmbedInternals.ssoAuthorizeURL(
            baseURL: portal, provider: "evilcorp", clientID: nil, email: nil, nativeRedirect: nil)
        XCTAssertTrue(u!.absoluteString.contains("/sso/google/"))
    }

    func testSsoURL_microsoftAllowed() {
        let u = EmbedInternals.ssoAuthorizeURL(
            baseURL: portal, provider: "microsoft", clientID: nil, email: nil, nativeRedirect: nil)
        XCTAssertTrue(u!.absoluteString.contains("/sso/microsoft/"))
    }

    func testSsoURL_omitsNullClientAndAbsentFields() {
        let u = EmbedInternals.ssoAuthorizeURL(
            baseURL: portal, provider: "google", clientID: "null", email: nil, nativeRedirect: nil)
        XCTAssertNil(query(u, "client_id"))
        XCTAssertNil(query(u, "login_hint"))
        XCTAssertNil(query(u, "native_redirect"))
        XCTAssertEqual(query(u, "native"), "1")
    }

    // MARK: scheme(ofCallback:)
    func testScheme_extractsScheme() {
        XCTAssertEqual(EmbedInternals.scheme(ofCallback: "aiqexample://sso-callback"), "aiqexample")
        XCTAssertEqual(EmbedInternals.scheme(ofCallback: "applaudiq://sso-callback"), "applaudiq")
    }

    // MARK: parseCode / parseError
    func testParseCode_happy() {
        XCTAssertEqual(EmbedInternals.parseCode(from: URL(string: "aiqexample://sso-callback?code=abc123")!), "abc123")
    }

    func testParseCode_absentOnError() {
        XCTAssertNil(EmbedInternals.parseCode(from: URL(string: "aiqexample://sso-callback?error=nope")!))
    }

    func testParseError_happyDecoded() {
        let u = URL(string: "applaudiq://sso-callback?error=This%20login%20was%20started%20for%20a%40b.com.")!
        XCTAssertEqual(EmbedInternals.parseError(from: u), "This login was started for a@b.com.")
    }

    func testParseError_absentOnSuccess() {
        XCTAssertNil(EmbedInternals.parseError(from: URL(string: "applaudiq://sso-callback?code=abc")!))
    }

    func testParseCodeError_emptyValuesAreNil() {
        XCTAssertNil(EmbedInternals.parseCode(from: URL(string: "applaudiq://sso-callback?code=")!))
        XCTAssertNil(EmbedInternals.parseError(from: URL(string: "applaudiq://sso-callback?error=")!))
    }
}
