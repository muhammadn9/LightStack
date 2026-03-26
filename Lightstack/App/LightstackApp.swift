import SwiftUI

@main
struct LightstackApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
    }
}
