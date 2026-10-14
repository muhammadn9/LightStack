import SwiftUI

@main
struct LightstackApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, environment.isAuthenticated {
                        environment.syncService.triggerFlush()
                    }
                }
                .onOpenURL { url in
                    environment.authService.handleDeepLink(url)
                }
        }
    }
}
