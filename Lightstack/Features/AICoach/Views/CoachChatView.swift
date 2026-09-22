import SwiftUI

/// Conversational chat view with the AI coach.
/// Ephemeral per session — messages are held in memory only, not persisted.
struct CoachChatView: View {
    @ObservedObject var viewModel: CoachChatViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                systemBanner
                messageList
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .themedBackground()
            .navigationTitle("Coach Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .alert("Workout Modification", isPresented: $viewModel.showModificationConfirmation) {
                Button("Apply Changes", role: .none) {
                    viewModel.confirmModifications(applyTo: todayViewModel)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.rejectModifications()
                }
            } message: {
                Text(modificationMessage)
            }
        }
    }

    private var modificationMessage: String {
        let changes = viewModel.pendingModifications.map { $0.description }
        let body = "The coach suggested these changes:\n\n" + changes.joined(separator: "\n")
        guard viewModel.requiresExplicitConfirmation else { return body }
        return body + "\n\nWe're not fully confident this is what you asked for — please double-check before applying."
    }

    // MARK: - System Banner

    private var systemBanner: some View {
        Text("Chat with your coach about this session")
            .font(AppTheme.caveat(12))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceElevated)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Skip first context message (index 0) — it's internal context
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        if index > 0 {
                            MessageBubbleView(message: message)
                        }
                    }

                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .tint(AppTheme.accent)
                            Text("Coach is thinking...")
                                .font(AppTheme.caveat(12))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .id("loading")
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                withAnimation {
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask your coach...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(AppTheme.caveat(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .foregroundStyle(AppTheme.textPrimary)

            Button(action: { viewModel.sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading
                            ? AppTheme.textSecondary
                            : AppTheme.accent
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }
}
