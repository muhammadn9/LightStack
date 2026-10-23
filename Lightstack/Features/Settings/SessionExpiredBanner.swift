import SwiftUI

/// Non-blocking banner shown while the account's session is expired or revoked. Local data and
/// queued changes are kept; signing in as the same user resumes backing up.
struct SessionExpiredBanner: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        BannerContent(model: environment.backupStatus) { environment.beginReauthentication() }
    }

    private struct BannerContent: View {
        @ObservedObject var model: BackupStatusModel
        let signIn: () -> Void

        var body: some View {
            if model.sessionExpired {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(AppTheme.warning)
                    Text("You've been signed out \u{2014} sign in again to keep backing up")
                        .font(AppTheme.playfairItalic(13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sessionExpired.message")
                    Spacer(minLength: 8)
                    Button(action: signIn) {
                        Text("Sign in")
                            .font(AppTheme.playfairItalic(13, weight: .bold))
                            .foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("sessionExpired.signIn")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceElevated)
                .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 0.5) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sessionExpired.banner")
            }
        }
    }
}

/// Settings row: "All changes backed up" / "N changes waiting" / "Backing up..." / "Signed out".
/// Tapping backs up now (or starts signing in again when signed out).
struct BackupStatusRow: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        RowContent(model: environment.backupStatus) {
            if environment.backupStatus.status == .signedOut {
                environment.beginReauthentication()
            } else {
                environment.flushReviving()
                environment.backupStatus.refresh()
            }
        }
    }

    private struct RowContent: View {
        @ObservedObject var model: BackupStatusModel
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: model.status.systemImage)
                        .foregroundStyle(model.status == .signedOut ? AppTheme.warning : AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.status.title)
                            .foregroundStyle(AppTheme.textPrimary)
                        if let sub = model.status.subtitle() {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.backupStatus")
            .listRowBackground(AppTheme.surface)
            .task {
                // Keeps "Last backed up 5 minutes ago" fresh while the screen is visible.
                while !Task.isCancelled {
                    await model.refreshNow()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
        }
    }
}
