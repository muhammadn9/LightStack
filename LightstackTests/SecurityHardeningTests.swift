import XCTest
import CryptoKit
import CoreData
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

// MARK: - Local data protection

final class LocalDataProtectionTests: XCTestCase {

    func testStoreDescriptionCarriesFileProtection() {
        let description = NSPersistentStoreDescription()
        LocalStorageService.applyFileProtection(to: description)
        let value = description.options[NSPersistentStoreFileProtectionKey] as? FileProtectionType
        XCTAssertEqual(value, .completeUntilFirstUserAuthentication)
    }

    func testReleaseModeDebugStoreKeepsSizesNotText() throws {
        let suite = "coach-redact-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CoachDebugStore(defaults: defaults, redactContent: true)
        let me = UUID()
        store.recordRequest(userId: me, workoutType: "Push", model: "m", systemPromptName: "plan",
                            systemPromptLength: 10, userMessage: "my secret goals")
        store.recordResponse(userId: me, raw: "private reply", adjustments: ["detail"])
        let snapshot = try XCTUnwrap(store.lastPlan(forUser: me))
        XCTAssertEqual(snapshot.userMessage, "[redacted, 15 chars]")
        XCTAssertEqual(snapshot.rawResponse, "[redacted, 13 chars]")
        XCTAssertTrue(snapshot.adjustments.isEmpty)
        let stored = try XCTUnwrap(defaults.data(forKey: CoachDebugStore.defaultsKey))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("secret"))
    }

    func testDebugSnapshotExpires() throws {
        let suite = "coach-expiry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CoachDebugStore(defaults: defaults, redactContent: false)
        let me = UUID()
        store.recordRequest(userId: me, workoutType: "Push", model: "m", systemPromptName: "plan",
                            systemPromptLength: 1, userMessage: "x",
                            now: Date().addingTimeInterval(-CoachDebugStore.maxAge - 60))
        XCTAssertNil(store.lastPlan(forUser: me))
        XCTAssertNil(defaults.data(forKey: CoachDebugStore.defaultsKey))
    }

    func testClearAllRemovesSharedSnapshot() {
        let me = UUID()
        CoachDebugStore.shared.recordRequest(userId: me, workoutType: "Push", model: "m",
                                             systemPromptName: "plan", systemPromptLength: 1, userMessage: "x")
        CoachDebugStore.clearAll()
        XCTAssertNil(CoachDebugStore.shared.lastPlan(forUser: me))
    }

    func testDiagnosticsClearRemovesFile() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiagnosticsStore(directory: dir)
        store.append([DiagnosticEntry(id: "1", date: Date(), kind: .crash, summary: "s")])
        XCTAssertEqual(store.load().count, 1)
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testWipeAllUserDataRemovesEverything() {
        let storage = LocalStorageService(inMemory: true)
        let me = UUID()
        storage.saveProfile(UserProfile(
            id: me, userId: me, displayName: nil, age: nil, heightInches: nil, weightLbs: nil,
            trainingAgeMonths: nil, primaryGoals: [], splitDays: [], avoidExercises: [], equipment: [:],
            customEquipment: nil, notesToCoach: nil, createdAt: Date(), updatedAt: Date()))
        XCTAssertNotNil(storage.fetchProfile(userId: me))
        XCTAssertTrue(storage.wipeAllUserData())
        XCTAssertNil(storage.fetchProfile(userId: me))
    }
}
