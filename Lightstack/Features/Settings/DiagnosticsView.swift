import SwiftUI

/// Recent crash / hang diagnostics collected on this device by MetricKit, with a Share button.
struct DiagnosticsView: View {
    @State private var entries: [DiagnosticEntry] = []
    @State private var exportURL: URL?

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No diagnostics yet. Crash and freeze reports appear here after iOS delivers them, usually within a day.")
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
                    .accessibilityIdentifier("diagnostics.empty")
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.kind.label).font(.headline)
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Text(entry.summary).font(.subheadline)
                    ForEach(Array(entry.frames.prefix(4).enumerated()), id: \.offset) { _, frame in
                        Text(frame)
                            .font(AppTheme.plexMono(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(AppTheme.surface)
            }
            if let exportURL, !entries.isEmpty {
                ShareLink(item: exportURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("diagnostics.share")
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("diagnostics.screen")
        .onAppear {
            entries = DiagnosticsStore.shared.load()
            exportURL = DiagnosticsStore.shared.exportFile()
        }
    }
}
