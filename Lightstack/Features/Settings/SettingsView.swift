import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("appColorScheme") private var colorScheme = "system"
    @AppStorage("restTimerNotificationsEnabled") private var restTimerNotif = true
    @AppStorage(RestPreference.key) private var defaultRestSeconds = 90
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage(LiveActivityController.settingKey) private var liveActivityEnabled = true
    @State private var unsyncedCount = 0
    @State private var showUnsyncedAlert = false
    @State private var showDeleteAccount = false
    @State private var showPrivacyInfo = false
    @State private var aiConsentGranted = AIConsent.isGranted

    // Pushed from Profile's NavigationStack (gear button), so it uses the
    // system navigation bar for its title and back button.
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $colorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.surface)
                }

                Section("Notifications") {
                    Toggle("Rest Timer Alerts", isOn: $restTimerNotif)
                        .tint(AppTheme.accent)
                        .listRowBackground(AppTheme.surface)

                    if LiveActivityController.isSystemAvailable {
                        Toggle("Live Activity on lock screen", isOn: $liveActivityEnabled)
                            .tint(AppTheme.accent)
                            .accessibilityIdentifier("settings.liveActivityToggle")
                            .listRowBackground(AppTheme.surface)
                            .onChange(of: liveActivityEnabled) { _, _ in
                                LiveActivityController.shared.settingChanged()
                            }
                    }
                }

                Section("Workout") {
                    Picker("Default Rest Timer", selection: $defaultRestSeconds) {
                        Text("1 min").tag(60)
                        Text("1.5 min").tag(90)
                        Text("2 min").tag(120)
                        Text("2.5 min").tag(150)
                        Text("3 min").tag(180)
                        Text("4 min").tag(240)
                        Text("5 min").tag(300)
                    }
                    .listRowBackground(AppTheme.surface)

                    Picker("Weight Unit", selection: $weightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                    .listRowBackground(AppTheme.surface)
                }

                Section("Backup") {
                    BackupStatusRow()
                    NavigationLink(destination: DiagnosticsView()) {
                        Text("Diagnostics")
                    }
                    .accessibilityIdentifier("settings.diagnostics")
                    .listRowBackground(AppTheme.surface)
                }

                #if DEBUG
                AIUsageDebugSection()
                SyncQueueDebugSection()
                #endif

                Section {
                    Toggle("AI coaching (Google Gemini)", isOn: Binding(
                        get: { aiConsentGranted },
                        set: { aiConsentGranted = $0; AIConsent.set($0) }
                    ))
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("settings.aiConsentToggle")
                    .listRowBackground(AppTheme.surface)

                    if let url = PrivacyPolicy.url {
                        Link(destination: url) {
                            Text("Privacy Policy")
                        }
                        .accessibilityIdentifier("settings.privacyPolicy")
                        .listRowBackground(AppTheme.surface)
                    } else {
                        Button("Privacy Policy") { showPrivacyInfo = true }
                            .accessibilityIdentifier("settings.privacyPolicy")
                            .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("When on, your workout history, profile stats and notes to the coach are sent to Google Gemini through LightStack's server to write coaching. When off, no AI requests are made.")
                }

                Section("Account") {
                    Button(action: requestSignOut) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(AppTheme.playfairItalic(14, weight: .bold))
                        .foregroundStyle(AppTheme.destructive)
                    }
                    .accessibilityIdentifier("settings.signOutButton")
                    .listRowBackground(AppTheme.surface)
                }

                Section {
                    Button(action: { showDeleteAccount = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete account")
                        }
                        .font(AppTheme.playfairItalic(14, weight: .bold))
                        .foregroundStyle(AppTheme.destructive)
                    }
                    .accessibilityIdentifier("settings.deleteAccountButton")
                    .listRowBackground(AppTheme.surface)
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text("Permanently deletes your account and all of your data.")
                }
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet()
            }
            .sheet(isPresented: $showPrivacyInfo) {
                NavigationStack { PrivacyInfoView() }
            }
            .scrollContentBackground(.hidden)
            .alert("Some changes haven't backed up yet", isPresented: $showUnsyncedAlert) {
                Button("Sign Out", role: .destructive) { environment.authService.signOut() }
                    .accessibilityIdentifier("settings.unsynced.signOut")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("settings.unsynced.cancel")
            } message: {
                Text("\(unsyncedCount) \(unsyncedCount == 1 ? "change is" : "changes are") saved on this iPhone but not yet uploaded. They'll upload next time you sign in on this device.")
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("settings.screen")
    }
}

extension SettingsView {
    /// Warns before sign-out when the offline queue still holds changes for this user.
    fileprivate func requestSignOut() {
        Task {
            let pending = await environment.offlineQueueManager.pendingCount
            let failed = await environment.offlineQueueManager.failedCount
            await MainActor.run {
                if pending + failed > 0 {
                    unsyncedCount = pending + failed
                    showUnsyncedAlert = true
                } else {
                    environment.authService.signOut()
                }
            }
        }
    }
}

#if DEBUG
/// Offline queue status and dead-letter retry. Debug builds only.
private struct SyncQueueDebugSection: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var pending = 0
    @State private var failed = 0

    var body: some View {
        Section("Sync queue (debug)") {
            Text("Sync queue: \(pending) pending, \(failed) failed")
                .accessibilityIdentifier("settings.syncQueue.status")
                .listRowBackground(AppTheme.surface)
            Button("Retry failed") {
                Task {
                    await environment.offlineQueueManager.retryFailed()
                    await refresh()
                    environment.syncService.triggerFlush()
                }
            }
            .accessibilityIdentifier("settings.syncQueue.retry")
            .listRowBackground(AppTheme.surface)
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refresh() async {
        pending = await environment.offlineQueueManager.pendingCount
        failed = await environment.offlineQueueManager.failedCount
    }
}

/// Today's AI calls and tokens per task (from Gemini usageMetadata). Debug builds only.
private struct AIUsageDebugSection: View {
    @State private var rows: [(task: AITask, entry: AIUsageTracker.Entry)] = []

    var body: some View {
        Section("AI usage (debug)") {
            if rows.isEmpty {
                Text("No AI calls today").foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            }
            ForEach(rows, id: \.task) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.task.label): \(row.entry.calls) calls")
                    Text("prompt \(row.entry.prompt) · out \(row.entry.candidates) · think \(row.entry.thoughts) · total \(row.entry.total)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
            Button("Refresh") { rows = AIUsageTracker.shared.snapshot() }
                .listRowBackground(AppTheme.surface)
            Button("Reset", role: .destructive) {
                AIUsageTracker.shared.reset()
                rows = AIUsageTracker.shared.snapshot()
            }
            .listRowBackground(AppTheme.surface)
        }
        .onAppear { rows = AIUsageTracker.shared.snapshot() }
    }
}
#endif

// MARK: - AI consent

/// Whether the user has allowed LightStack to send training data to the third-party AI (Google
/// Gemini, via LightStack's server). Stored per device in UserDefaults.
enum AIConsent {
    static let key = "ai.thirdPartyConsent.v1"
    static let dateKey = "ai.thirdPartyConsent.v1.date"
    /// Set once the user has answered the consent sheet either way, so "Not now" isn't re-asked.
    static let promptedKey = "ai.thirdPartyConsent.v1.prompted"

    /// Convenience for call sites: `guard AIConsent.isGranted else { ... }`.
    static var isGranted: Bool { granted() }

    /// UI-test mode (DEBUG) auto-grants so existing tests keep working.
    static func granted(in defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        if UITestMode.isActive { return true }
        #endif
        return defaults.bool(forKey: key)
    }

    static func set(_ granted: Bool, in defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(granted, forKey: key)
        defaults.set(now, forKey: dateKey)
        defaults.set(true, forKey: promptedKey)
    }

    /// When the current answer was given.
    static func decisionDate(in defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: dateKey) as? Date
    }

    /// True when the one-time consent sheet should appear.
    static func shouldPrompt(in defaults: UserDefaults = .standard) -> Bool {
        !granted(in: defaults) && !defaults.bool(forKey: promptedKey)
    }

    /// Error to return to callers when AI is requested without consent.
    static let deniedError = NSError(
        domain: "AIConsent", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "AI coaching is off. Turn it on in Settings, Privacy, to let LightStack send your training data to Google Gemini."]
    )
}

// MARK: - Privacy policy / data summary

enum PrivacyPolicy {
    /// `LSPrivacyPolicyURL` from Info.plist; nil when missing, empty or not an https URL.
    static var url: URL? { url(from: Bundle.main.object(forInfoDictionaryKey: "LSPrivacyPolicyURL") as? String) }

    static func url(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil
        else { return nil }
        return url
    }

    /// Short in-app summary of docs/privacy/DATA_INVENTORY.md.
    static let summary: [(title: String, detail: String)] = [
        ("Account", "Email address (or Apple / Google sign-in identity), handled by Supabase Auth."),
        ("Profile", "Display name, age, height, weight, training experience, goals, equipment, exercises to avoid and notes to the coach."),
        ("Training", "Workouts, exercises, sets (weight, reps, RIR), personal records, plans, rest days and coach summaries."),
        ("Nutrition", "Foods, meals, water, daily notes, targets and plans you log."),
        ("Where it lives", "On your iPhone and in your LightStack account on Supabase. Deleting your account removes both."),
        ("AI coaching", "With your permission, your profile stats, goals, notes, recent workouts and chat messages go through LightStack's server to Google Gemini to write coaching. Your name and email are not needed for this."),
        ("Barcode and food search", "Barcodes and search words you type are sent to Open Food Facts."),
        ("Your choices", "Turn AI coaching off any time in Settings. Delete your account and all data in Settings, Delete account.")
    ]
}

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section {
                ForEach(PrivacyPolicy.summary, id: \.title) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(AppTheme.playfairItalic(15, weight: .bold))
                        Text(item.detail).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            } footer: {
                if let url = PrivacyPolicy.url {
                    Link("Read the full privacy policy", destination: url)
                } else {
                    Text("Policy URL not configured. This summary describes what the app does.")
                        .accessibilityIdentifier("privacy.urlNotConfigured")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacy.info")
    }
}

/// One-time sheet asking permission to send data to the third-party AI.
struct AIConsentSheet: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.accent)
                Text("Allow AI coaching?")
                    .font(AppTheme.playfairItalic(26, weight: .bold))
                Text("To write your plans and coaching, LightStack sends your workout history, profile stats (age, height, weight, goals, training experience) and your notes to the coach to Google Gemini, through LightStack's server. It is used only to generate your coaching.")
                    .foregroundStyle(AppTheme.textSecondary)
                Text("You can change this any time in Settings. Without it, the rest of the app works and no AI requests are made.")
                    .foregroundStyle(AppTheme.textSecondary)
                if let url = PrivacyPolicy.url {
                    Link("Privacy policy", destination: url)
                        .accessibilityIdentifier("aiConsent.privacyLink")
                } else {
                    NavigationLink("What data is used") { PrivacyInfoView() }
                        .accessibilityIdentifier("aiConsent.privacyLink")
                }
                Spacer()
                Button(action: { onDecision(true) }) {
                    Text("Allow")
                        .font(AppTheme.playfairItalic(17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(AppTheme.onAccent)
                }
                .accessibilityIdentifier("aiConsent.allow")
                Button("Not now") { onDecision(false) }
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("aiConsent.notNow")
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("aiConsent.sheet")
    }
}

// MARK: - Delete account

struct DeleteAccountSheet: View {
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case idle, deleting, failed(String), done
    }

    static let confirmWord = "DELETE"

    @State private var typed = ""
    @State private var phase: Phase = .idle
    @State private var appleCode: String?

    /// The confirm button is enabled only when exactly `DELETE` is typed and no deletion is running.
    static func canConfirm(typed: String, phase: Phase) -> Bool {
        typed == confirmWord && phase != .deleting && phase != .done
    }

    private var canConfirm: Bool { Self.canConfirm(typed: typed, phase: phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete your account?")
                        .font(AppTheme.playfairItalic(26, weight: .bold))
                    Text("All of your workouts, nutrition and coach data will be permanently deleted from LightStack's cloud and from this iPhone. This can't be undone.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("deleteAccount.explanation")

                    if environment.authService.hasAppleIdentity {
                        appleSection
                    }

                    Text("Type \(Self.confirmWord) to confirm")
                        .font(.subheadline.weight(.semibold))
                    TextField(Self.confirmWord, text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border))
                        .disabled(phase == .deleting || phase == .done)
                        .accessibilityIdentifier("deleteAccount.confirmField")

                    statusView

                    Button(action: startDeletion) {
                        HStack {
                            if phase == .deleting { ProgressView().tint(.white) }
                            Text(buttonTitle)
                        }
                        .font(AppTheme.playfairItalic(17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .background(AppTheme.destructive.opacity(canConfirm ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("deleteAccount.confirmButton")

                    Button("Cancel") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .foregroundStyle(AppTheme.textSecondary)
                        .disabled(phase == .deleting)
                        .accessibilityIdentifier("deleteAccount.cancelButton")
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(phase == .deleting || phase == .done)
        .accessibilityIdentifier("deleteAccount.sheet")
    }

    private var buttonTitle: String {
        switch phase {
        case .deleting: return "Deleting..."
        case .failed: return "Retry delete"
        case .done: return "Deleted"
        case .idle: return "Delete account permanently"
        }
    }

    @ViewBuilder private var statusView: some View {
        switch phase {
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.destructive)
                .accessibilityIdentifier("deleteAccount.error")
        case .done:
            Text("Your account was deleted.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.success)
                .accessibilityIdentifier("deleteAccount.success")
        case .deleting:
            Text("Deleting your data. Keep the app open.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("deleteAccount.progress")
        case .idle:
            EmptyView()
        }
    }

    /// Optional re-authorization so the server can revoke the Apple token (App Store requirement).
    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You signed in with Apple. Authorize once more so LightStack can disconnect it from your Apple ID.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            if appleCode == nil {
                SignInWithAppleButton(.continue, onRequest: { $0.requestedScopes = [] }, onCompletion: { result in
                    if case .success(let auth) = result,
                       let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                       let data = credential.authorizationCode,
                       let code = String(data: data, encoding: .utf8) {
                        appleCode = code
                    }
                })
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 44)
                .disabled(phase == .deleting)
                .accessibilityIdentifier("deleteAccount.appleAuthorize")
            } else {
                Label("Apple authorization ready", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.success)
            }
        }
    }

    private func startDeletion() {
        guard canConfirm else { return }
        phase = .deleting
        let steps = LiveAccountDeletionSteps(
            authService: environment.authService,
            offlineQueue: environment.offlineQueueManager,
            localStorage: environment.localStorageService
        )
        let code = appleCode
        Task {
            do {
                try await AccountDeletionCoordinator(steps: steps).run(appleAuthorizationCode: code)
                phase = .done
            } catch {
                // Cloud deletion failed: nothing local was touched.
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
