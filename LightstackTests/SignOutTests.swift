import XCTest
import Supabase
@testable import Lightstack

@MainActor
final class SignOutTests: XCTestCase {

    private final class Recorder: AuthServiceDelegate {
        var signedOut = 0
        var errors = 0
        func authServiceDidSignIn(_ service: AuthService) {}
        func authServiceDidSignOut(_ service: AuthService) { signedOut += 1 }
        func authServiceNeedsEmailVerification(_ service: AuthService, email: String) {}
        func authService(_ service: AuthService, didFailWith error: Error) { errors += 1 }
    }

    private func makeService() -> AuthService {
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test"
        )
        return AuthService(client: client)
    }

    func testOfflineServerFailureStillSignsOutLocally() async {
        let service = makeService()
        let recorder = Recorder()
        service.delegate = recorder
        service.remoteSignOutOverride = { throw URLError(.notConnectedToInternet) }
        await service.performSignOut()
        XCTAssertEqual(recorder.signedOut, 1)
        XCTAssertEqual(recorder.errors, 0)
    }

    func testServerSuccessSignsOut() async {
        let service = makeService()
        let recorder = Recorder()
        service.delegate = recorder
        service.remoteSignOutOverride = {}
        await service.performSignOut()
        XCTAssertEqual(recorder.signedOut, 1)
    }

    func testRealClientWithoutSessionSignsOut() async {
        let service = makeService()
        let recorder = Recorder()
        service.delegate = recorder
        await service.performSignOut()
        XCTAssertEqual(recorder.signedOut, 1)
    }
}
