import SwiftUI
import UIKit

/// Sheet that walks the user through importing past workouts from AI-formatted JSON.
struct WorkoutImportView: View {
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    let onImported: () -> Void

    @State private var pastedText = ""
    @State private var preview: ImportPreview?
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        stepOne
                        stepTwo
                        stepThree
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Steps

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1. Copy the prompt")
            Text("Copy this prompt into ChatGPT, Gemini, Claude or any AI, then paste your workout notes after it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Button {
                UIPasteboard.general.string = WorkoutImportPrompt.text
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copied = false
                }
            } label: {
                Label(copied ? "Copied ✓" : "Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(WaxSealButtonStyle())
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("2. Paste the AI's reply")
            TextEditor(text: $pastedText)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Pasted AI reply")
                .onChange(of: pastedText) { _, _ in
                    preview = nil
                    errorMessage = nil
                }
            Button {
                if let text = UIPasteboard.general.string { pastedText = text }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(WaxSealButtonStyle(isSecondary: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("3. Check and import")
            Button {
                check()
            } label: {
                Label("Check", systemImage: "checkmark.circle")
            }
            .buttonStyle(WaxSealButtonStyle(isSecondary: true))
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.destructive)
            }

            if let preview {
                Text(summaryLine(preview))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                ForEach(Array(preview.skipped.enumerated()), id: \.offset) { _, reason in
                    Text(skipText(reason))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if !preview.toImport.isEmpty {
                    let n = preview.toImport.count
                    Button {
                        runImport(preview)
                    } label: {
                        Text("Import \(n) workout\(n == 1 ? "" : "s")")
                    }
                    .buttonStyle(WaxSealButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions

    private func makeService() -> WorkoutImportService {
        WorkoutImportService(
            workoutRepository: environment.workoutRepository,
            prRepository: environment.prRepository,
            userId: userId
        )
    }

    private func check() {
        do {
            let result = try WorkoutImportParser.parse(pastedText)
            preview = makeService().preview(result)
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = "Couldn't find workout data — make sure you pasted the AI's whole reply."
        }
    }

    private func runImport(_ preview: ImportPreview) {
        makeService().importWorkouts(preview.toImport)
        onImported()
        dismiss()
    }

    // MARK: - Text

    private func summaryLine(_ p: ImportPreview) -> String {
        let n = p.toImport.count
        return "\(n) workout\(n == 1 ? "" : "s") ready · \(p.duplicateCount) already in History · \(p.skipped.count) skipped"
    }

    private func skipText(_ reason: ImportSkipReason) -> String {
        switch reason {
        case .noDate(let name):
            return "\(name ?? "Workout"): no date"
        case .noExercises(let name, let date):
            if let date {
                let d = date.formatted(.dateTime.month(.abbreviated).day())
                return "\(name ?? "Workout") on \(d): no exercises"
            }
            return "\(name ?? "Workout"): no exercises"
        }
    }
}
