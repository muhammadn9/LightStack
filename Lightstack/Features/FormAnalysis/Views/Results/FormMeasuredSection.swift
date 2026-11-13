import SwiftUI

/// What the on-device tracker measured: findings, most severe first, or one clear card when nothing could be.
struct FormMeasuredSection: View {

    let findings: [FormFinding]
    let untrackable: FormFinding?
    let cameraTip: String
    let onSelect: (FormFinding) -> Void
    let onRecordAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(title: "From tracking", systemImage: "viewfinder")
            if let untrackable {
                untrackableCard(untrackable)
            } else {
                ForEach(findings) { finding in
                    FindingCard(finding: finding) { onSelect(finding) }
                }
            }
        }
    }

    private func untrackableCard(_ finding: FormFinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: finding.id == "untracked" ? "info.circle.fill" : "eye.slash.fill")
                    .foregroundStyle(finding.id == "untracked" ? AppTheme.textSecondary : AppTheme.warning)
                Text(finding.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text(finding.detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // The detail already ends with the camera tip for can't-track cases; don't repeat it.
            if finding.id != "untracked", !finding.detail.contains(cameraTip) {
                Label(cameraTip, systemImage: "camera.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if finding.id != "untracked" {
                Button(action: onRecordAgain) {
                    Text("Record again")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                        .background(AppTheme.accent, in: Capsule())
                }
                .accessibilityIdentifier("formResults.cardRecordAgain")
            }
        }
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formResults.finding.\(finding.id)")
    }
}

private struct FindingCard: View {
    let finding: FormFinding
    let action: () -> Void

    private var color: Color {
        switch finding.severity {
        case .good: return AppTheme.success
        case .minor: return AppTheme.warning
        case .major: return AppTheme.destructive
        }
    }

    private var icon: String {
        switch finding.severity {
        case .good: return "checkmark.circle.fill"
        case .minor: return "exclamationmark.circle.fill"
        case .major: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(finding.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if finding.time != nil {
                        Image(systemName: "play.circle.fill").foregroundStyle(AppTheme.accent)
                    }
                }
                Text(finding.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !finding.cue.isEmpty {
                    Text(finding.cue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(finding.time != nil ? "Shows this moment in the replay" : "")
        .accessibilityIdentifier("formResults.finding.\(finding.id)")
    }
}
