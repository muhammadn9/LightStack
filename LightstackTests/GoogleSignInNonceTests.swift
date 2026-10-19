import XCTest
import CryptoKit
@testable import Lightstack

final class GoogleSignInNonceTests: XCTestCase {

    private func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testNonceHashMatchesRaw() {
        let n = AuthService.appleNonce()
        XCTAssertEqual(n.hashed, sha256Hex(n.raw))
    }

    func testNoncesAreUnique() {
        XCTAssertNotEqual(AuthService.appleNonce().raw, AuthService.appleNonce().raw)
    }

    /// Google receives the hash; Supabase receives the raw value whose hash equals it.
    func testGoogleGetsHashAndSupabaseGetsMatchingRaw() async throws {
        var hashGivenToGoogle: String?
        var rawGivenToSupabase: String?
        try await AuthService.performGoogleExchange(
            obtainTokens: { hashed in
                hashGivenToGoogle = hashed
                return ("id", "access")
            },
            exchange: { idToken, accessToken, raw in
                XCTAssertEqual(idToken, "id")
                XCTAssertEqual(accessToken, "access")
                rawGivenToSupabase = raw
            }
        )
        let hash = try XCTUnwrap(hashGivenToGoogle)
        let raw = try XCTUnwrap(rawGivenToSupabase)
        XCTAssertEqual(hash, sha256Hex(raw))
        XCTAssertNotEqual(hash, raw)
    }

    func testFailedGoogleStepSkipsExchange() async {
        var exchanged = false
        do {
            try await AuthService.performGoogleExchange(
                obtainTokens: { _ in throw NSError(domain: "t", code: 1) },
                exchange: { _, _, _ in exchanged = true }
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertFalse(exchanged)
        }
    }
}
