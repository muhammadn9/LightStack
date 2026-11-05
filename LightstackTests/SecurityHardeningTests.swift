import XCTest
import CryptoKit
@testable import Lightstack

final class SecurityHardeningTests: XCTestCase {

    // MARK: - Apple Sign-In nonce

    func testAppleNonceHashIsSHA256OfRawValue() {
        let nonce = AuthService.appleNonce()
        XCTAssertEqual(nonce.raw.count, 32)
        let expected = SHA256.hash(data: Data(nonce.raw.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(nonce.hashed, expected)
    }

    func testAppleNoncesAreUnique() {
        XCTAssertNotEqual(AuthService.appleNonce().raw, AuthService.appleNonce().raw)
    }

    // MARK: - Deep links

    func testOnlyOwnAuthCallbackIsAccepted() throws {
        let ok = try XCTUnwrap(URL(string: "lightstack://auth-callback?code=abc"))
        let otherHost = try XCTUnwrap(URL(string: "lightstack://evil?access_token=x"))
        let otherScheme = try XCTUnwrap(URL(string: "https://auth-callback/x"))
        XCTAssertTrue(AuthService.isAuthCallback(ok))
        XCTAssertFalse(AuthService.isAuthCallback(otherHost))
        XCTAssertFalse(AuthService.isAuthCallback(otherScheme))
    }

    // MARK: - AI proxy

    func testProxyMessageIsReadFromErrorBody() throws {
        let data = try XCTUnwrap(#"{"error":{"message":"Daily AI limit reached. Try again tomorrow."}}"#.data(using: .utf8))
        XCTAssertEqual(GeminiService.proxyMessage(from: data), "Daily AI limit reached. Try again tomorrow.")
    }

    func testProxyRefusalIsNotRetriedOnAnotherModel() {
        let refusing = StubProvider(name: "first", result: .failure(GeminiService.proxyError(429, "Too many AI requests.")))
        let backup = StubProvider(name: "second", result: .success("should not be used"))
        let manager = AIServiceManager(providers: [refusing, backup])
        let done = expectation(description: "completion")
        manager.generateChat(systemPrompt: "s", messages: [], expectsJSON: false) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.localizedDescription, "Too many AI requests.")
            } else {
                XCTFail("Expected the proxy refusal to be returned")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(backup.calls, 0)
    }

    func testAppNoLongerShipsAIKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["GEMINI_API_KEY", "OPENAI_API_KEY", "CLAUDE_API_KEY"] {
            XCTAssertNil(info[key], "\(key) must not be in Info.plist")
        }
    }
}

private final class StubProvider: AIProvider {
    let name: String
    let result: Result<String, Error>
    private(set) var calls = 0
    var rateLimitKey: String { "stub_rate_limit_\(name)" }

    init(name: String, result: Result<String, Error>) {
        self.name = name
        self.result = result
        UserDefaults.standard.removeObject(forKey: "stub_rate_limit_\(name)")
    }

    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        calls += 1
        completion(result)
    }
}


// MARK: - Account deletion, AI consent, privacy URL

final class AccountPrivacyTests: XCTestCase {

    private func freshDefaults() throws -> UserDefaults {
        let name = "AccountPrivacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testConsentIsOffByDefaultAndPrompts() throws {
        let defaults = try freshDefaults()
        XCTAssertFalse(AIConsent.granted(in: defaults))
        XCTAssertTrue(AIConsent.shouldPrompt(in: defaults))
    }

    func testConsentPersistsWithDateAndStopsPrompting() throws {
        let defaults = try freshDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        AIConsent.set(true, in: defaults, now: now)
        XCTAssertTrue(defaults.bool(forKey: "ai.thirdPartyConsent.v1"))
        XCTAssertEqual(AIConsent.decisionDate(in: defaults), now)
        XCTAssertFalse(AIConsent.shouldPrompt(in: defaults))
    }

    func testNotNowIsNotAskedAgainAndCanBeGrantedLater() throws {
        let defaults = try freshDefaults()
        AIConsent.set(false, in: defaults)
        XCTAssertFalse(AIConsent.shouldPrompt(in: defaults))
        XCTAssertFalse(defaults.bool(forKey: AIConsent.key))
        AIConsent.set(true, in: defaults)
        XCTAssertTrue(defaults.bool(forKey: AIConsent.key))
    }

    func testPrivacyPolicyURLMustBeHTTPS() {
        XCTAssertNil(PrivacyPolicy.url(from: nil))
        XCTAssertNil(PrivacyPolicy.url(from: "  "))
        XCTAssertNil(PrivacyPolicy.url(from: "http://example.com/p"))
        XCTAssertNil(PrivacyPolicy.url(from: "javascript:alert(1)"))
        XCTAssertEqual(PrivacyPolicy.url(from: " https://example.com/privacy ")?.absoluteString, "https://example.com/privacy")
    }

    func testDeleteConfirmRequiresExactWord() {
        XCTAssertFalse(DeleteAccountSheet.canConfirm(typed: "", phase: .idle))
        XCTAssertFalse(DeleteAccountSheet.canConfirm(typed: "delete", phase: .idle))
        XCTAssertFalse(DeleteAccountSheet.canConfirm(typed: "DELETE ", phase: .idle))
        XCTAssertTrue(DeleteAccountSheet.canConfirm(typed: "DELETE", phase: .idle))
        XCTAssertTrue(DeleteAccountSheet.canConfirm(typed: "DELETE", phase: .failed("x")))
        XCTAssertFalse(DeleteAccountSheet.canConfirm(typed: "DELETE", phase: .deleting))
    }

    // MARK: Ordering

    private final class FakeSteps: AccountDeletionSteps {
        var log: [String] = []
        var remoteError: Error?
        func deleteRemoteAccount(appleAuthorizationCode: String?) async throws {
            log.append("remote")
            if let remoteError { throw remoteError }
        }
        func clearOfflineQueue() async { log.append("queue") }
        func wipeLocalData() async { log.append("wipe") }
        func signOutToLogin() async { log.append("signOut") }
    }

    func testDeletionRunsCloudThenQueueThenWipeThenSignOut() async throws {
        let steps = FakeSteps()
        try await AccountDeletionCoordinator(steps: steps).run()
        XCTAssertEqual(steps.log, ["remote", "queue", "wipe", "signOut"])
    }

    func testFailedCloudDeletionKeepsLocalData() async {
        let steps = FakeSteps()
        steps.remoteError = AccountDeletionError.offline
        do {
            try await AccountDeletionCoordinator(steps: steps).run()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(steps.log, ["remote"])
        }
    }
}
