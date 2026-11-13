import SwiftUI

/// "Something off?": asks for the real rep count (optional) and offers the tracking data (no video) to the
/// share sheet as a JSON file the developer can drop straight into the pose fixtures.
struct FormShareDataSheet: View {

    let model: FormResultsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var repsText = ""
    @State private var fileURL: URL?

    private var trueReps: Int? {
        Int(repsText.trimmingCharacters(in: .whitespaces)).flatMap { (0...500).contains($0) ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This shares the tracked body positions for this set, so wrong counts or findings can be fixed. "
                     + "No video and no photos are included.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("How many reps did you really do? (optional)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    TextField("Real rep count", text: $repsText)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("formResults.shareData.reps")
                }

                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("Share tracking data", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("formResults.shareData.send")
                } else {
                    Text("Couldn't prepare the data.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Share tracking data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .onAppear { refresh() }
        .onChange(of: repsText) { _, _ in refresh() }
    }

    private func refresh() { fileURL = model.trackingDataFile(trueReps: trueReps) }
}
