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
                    Text("Nothing was changed: the draft went through every check as built.")
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

            if let reasons = s.reasons, !reasons.isEmpty {
                section("Coach's reasons") {
                    ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason.label.isEmpty ? reason.exercise : "\(reason.exercise) · \(reason.label)")
                                .font(AppTheme.caveat(12, weight: .bold))
                                .foregroundStyle(reason.label.hasPrefix("Coach wanted") ? AppTheme.warning : AppTheme.accent)
                            Text(reason.text)
                                .font(AppTheme.caveat(13))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("coachSaw.reasons")
            }

            if let review = s.review, !review.checks.isEmpty {
                section("Checks") {
                    Text(review.checksLine)
                        .font(AppTheme.caveat(14, weight: .bold))
                        .foregroundStyle(review.adjustedChecks.isEmpty ? AppTheme.success : AppTheme.warning)
                        .accessibilityIdentifier("coachSaw.checks.line")
                    ForEach(review.adjustedChecks, id: \.id) { check in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(AppTheme.caveat(12, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                            ForEach(check.adjustments, id: \.self) { line in
                                Text(line)
                                    .font(AppTheme.caveat(13))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("coachSaw.checks")
            }

            if let scorecard = s.scorecard {
                section("Is the coach helping?") {
                    Text(scorecard)
                        .font(AppTheme.caveat(13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coachSaw.scorecard")
                }
            }

            if let shared = s.nutritionShared {
                section("Nutrition sent to the coach") {
                    if !shared {
                        Text(Self.nutritionOffText)
                            .font(AppTheme.caveat(14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("coachSaw.nutritionOff")
                    } else {
                        if let fuel = s.fuelBlock { mono(fuel).accessibilityIdentifier("coachSaw.fuel") }
                        if s.mealsShared == false {
                            Text(Self.mealsOffText)
                                .font(AppTheme.caveat(14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("coachSaw.mealsOff")
                        } else if let meals = s.mealsBlock {
                            mono(meals).accessibilityIdentifier("coachSaw.meals")
                        }
                        if s.fuelBlock == nil, s.mealsBlock == nil, s.mealsShared != false {
                            Text(Self.noNutritionText)
                                .font(AppTheme.caveat(14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("coachSaw.nutritionNone")
                        }
                    }
                }
            }

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

    static let nutritionOffText = "Nutrition sharing is off"
    static let mealsOffText = "Pre-workout meal sharing is off"
    static let noNutritionText = "No nutrition data was available"

    /// The nutrition part of the copied text: the exact blocks sent, or why nothing was.
    static func nutritionText(_ s: CoachPlanSnapshot) -> [String] {
        guard let shared = s.nutritionShared else { return [] }
        var parts = ["", "NUTRITION SENT"]
        guard shared else { return parts + [nutritionOffText] }
        if let fuel = s.fuelBlock { parts.append(fuel) }
        if s.mealsShared == false { parts.append(mealsOffText) } else if let meals = s.mealsBlock { parts.append(meals) }
        if s.fuelBlock == nil, s.mealsBlock == nil, s.mealsShared != false { parts.append(noNutritionText) }
        return parts
    }

    /// What kind of change an adjustment line describes.
    static func kind(of line: String) -> String {
        if line.hasPrefix("Held the coach's") { return "Coach request held" }
        if line.contains("not a weight this lift has") { return "Weight check" }
        if line.contains("held at") && line.contains("because") { return "No-progress check" }
        if line.contains("reps held at") { return "Rep-jump rule" }
        if line.contains("hard sets is over") || line.contains("working sets is over") { return "Volume check" }
        if line.contains("to fit") && line.contains("minutes") { return "Time check" }
        if line.contains("named no evidence") { return "Evidence check" }
        if line.contains("dropped by the coach") { return "Coach dropped a lift" }
        if line.contains("swapped in") || line.contains("added with") { return "Calculated from your log" }
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
        if let reasons = s.reasons, !reasons.isEmpty {
            parts += ["", "COACH'S REASONS"] + reasons.map { "- \($0.exercise) [\($0.label)]: \($0.text)" }
        }
        if let review = s.review, !review.checks.isEmpty {
            parts += ["", "CHECKS", review.checksLine]
            for check in review.adjustedChecks { parts.append("- \(check.title): " + check.adjustments.joined(separator: "; ")) }
        }
        if let scorecard = s.scorecard { parts += ["", "SCORECARD", scorecard] }
        parts += nutritionText(s)
        parts += ["", "MESSAGE SENT", s.userMessage, "", "RAW REPLY", s.rawResponse ?? "(none)"]
        return parts.joined(separator: "\n")
    }
}
