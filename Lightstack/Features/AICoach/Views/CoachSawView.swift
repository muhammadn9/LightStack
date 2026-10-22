import SwiftUI
import UIKit

/// "What the coach saw": the last plan request, the AI's reply and what the app changed.
/// Shows only the signed-in user's own data, in every build.
struct CoachSawView: View {
    let userId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: CoachPlanSnapshot?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot {
                    content(snapshot)
                } else {
                    Text("Generate a plan to see what the coach used.")
                        .font(AppTheme.caveat(16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .accessibilityIdentifier("coachSaw.empty")
                }
            }
            .themedBackground()
            .navigationTitle("What the coach saw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("coachSaw.done")
                }
                if let snapshot {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(copied ? "Copied" : "Copy all") {
                            UIPasteboard.general.string = Self.allText(snapshot)
                            copied = true
                        }
                        .accessibilityIdentifier("coachSaw.copyAll")
                    }
                }
            }
        }
        .onAppear { snapshot = CoachDebugStore.shared.lastPlan(forUser: userId) }
    }

    private func content(_ s: CoachPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                row("When", s.timestamp.formatted(date: .abbreviated, time: .shortened))
                row("Model", s.model)
                row("Workout", s.workoutType)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coachSaw.summary")

            section("What the app decided") {
                if s.adjustments.isEmpty {
                    Text("Nothing was changed: the AI's numbers were used as given.")
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(Array(s.adjustments.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.kind(of: line))
                                .font(AppTheme.caveat(12, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                            Text(line)
                                .font(AppTheme.caveat(13))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .accessibilityIdentifier("coachSaw.adjustments")

            section("Message sent to the coach") {
                mono(s.userMessage).accessibilityIdentifier("coachSaw.userMessage")
            }
            section("Coach's raw reply") {
                mono(s.rawResponse ?? "No reply yet.").accessibilityIdentifier("coachSaw.rawResponse")
            }
        }
        .padding(16)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(AppTheme.caveat(14)).foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value).font(AppTheme.caveat(14, weight: .bold)).foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppTheme.playfairItalic(16, weight: .bold)).foregroundStyle(AppTheme.textPrimary)
            body()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Who set the numbers, from the adjustment line the plan builder wrote.
    static func kind(of line: String) -> String {
        if line.contains("engine set the targets") { return "Calculated from your log" }
        if line.contains("guardrail:") { return "AI estimate, adjusted by guardrails" }
        return "Note"
    }

    static func allText(_ s: CoachPlanSnapshot) -> String {
        var parts = [
            "When: \(s.timestamp.formatted(date: .abbreviated, time: .shortened))",
            "Model: \(s.model)",
            "Workout: \(s.workoutType)",
            "",
            "WHAT THE APP DECIDED"
        ]
        parts += s.adjustments.isEmpty ? ["(no changes)"] : s.adjustments.map { "- [\(kind(of: $0))] \($0)" }
        parts += ["", "MESSAGE SENT", s.userMessage, "", "RAW REPLY", s.rawResponse ?? "(none)"]
        return parts.joined(separator: "\n")
    }
}
