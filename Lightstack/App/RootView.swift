import SwiftUI

/// Root view that routes between Login, Email Verification, Onboarding,
/// and the main tab bar based on authentication and onboarding state.
struct RootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("appColorScheme") private var colorSchemePref = "system"
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        #if DEBUG
        if DesignLabConfig.isEnabled {
            DesignLabView()
        } else {
            appBody
        }
        #else
        appBody
        #endif
    }

    private var appBody: some View {
        Group {
            if environment.localStoreUnavailable {
                StoreUnavailableView()
            } else if environment.needsEmailVerification {
                EmailVerificationView()
            } else if !environment.isAuthenticated {
                LoginView()
            } else if environment.restoreGate != .idle {
                RestoreProgressView()
            } else if !environment.hasCompletedOnboarding {
                OnboardingView()
            } else {
                AppShellView()
            }
        }
        .keyboardDoneButton()
        .alert("Your data on this iPhone was set aside", isPresented: Binding(
            get: { environment.storeRecoveryNotice != nil && !environment.localStoreUnavailable },
            set: { if !$0 { environment.acknowledgeStoreRecoveryNotice() } }
        )) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("storeRecovery.ok")
        } message: {
            Text("Lightstack couldn't open the data saved on this iPhone. The old files were set aside safely, not deleted, and the app started with an empty library. Your backed-up data will be restored from your account.")
        }
        .animation(.easeInOut(duration: 0.3), value: environment.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: environment.needsEmailVerification)
        .animation(.easeInOut(duration: 0.3), value: environment.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: environment.restoreGate)
        .onAppear { applyColorScheme(colorSchemePref) }
        .onChange(of: colorSchemePref) { _, newValue in applyColorScheme(newValue) }
        .onChange(of: systemColorScheme) { _, _ in
            if colorSchemePref == "system" {
                applyColorScheme("system")
            }
        }
    }

    private func applyColorScheme(_ pref: String) {
        let style: UIUserInterfaceStyle
        switch pref {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}

/// Shown instead of the app when no local store, not even an empty one, could be created.
struct StoreUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.destructive)
            Text("Lightstack can't open its storage")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Nothing has been deleted. Close and reopen the app, and make sure your iPhone has free storage space. If this keeps happening, contact support before reinstalling so your backup can be checked first.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .accessibilityIdentifier("storeUnavailable.screen")
    }
}
