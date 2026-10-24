import SwiftUI

@main
struct LightstackApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    /// UI tests with `-uiTestingSkipLaunchFlush` ignore the first .active transition (app launch).
    @State private var ignoredLaunchActive = false
    #endif

    init() {
        // Live Activity buttons run in this process, even while it is backgrounded.
        LiveActivityActionRouter.handler = { action, setKey in
            await LiveActivityController.shared.handle(action, setKey: setKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    if phase == .active, UITestMode.isActive, UITestMode.skipLaunchFlush, !ignoredLaunchActive {
                        ignoredLaunchActive = true
                        return
                    }
                    #endif
                    if phase == .active, environment.isAuthenticated {
                        environment.syncService.triggerFlush()
                        environment.startBackgroundRestoreIfDue()
                    }
                }
                .onOpenURL { url in
                    environment.authService.handleDeepLink(url)
                }
        }
    }
}
