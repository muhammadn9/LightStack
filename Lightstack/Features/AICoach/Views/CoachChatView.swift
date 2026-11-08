import SwiftUI

/// Conversational chat view with the AI coach.
/// In a workout the thread is kept per workout (see `CoachThreadStore`); before a plan exists
/// (`.planning` mode) it is ephemeral and offers "Build today's plan".
struct CoachChatView: View {
    @ObservedObject var viewModel: CoachChatViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    /// Planning mode only: builds the plan with the chat's agreed notes (at most 300 characters).
    var onBuildPlan: ((String) -> Void)? = nil
    /// Planning mode only: false when no workout type is picked yet.
    var canBuildPlan: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var showGoals = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                systemBanner
                goalsSection
                messageList
                if let goal = viewModel.pendingGoal {
                    goalCard(goal)
                }
                planBar
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .themedBackground()
            .navigationTitle(viewModel.mode == .planning ? "Talk to the coach" : "Coach Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .sheet(isPresented: $viewModel.showModificationConfirmation) {
                ModificationConfirmationSheet(
                    modifications: viewModel.pendingModifications,
                    onApply: {
                        // Stay in the chat so the "✓ Updated …" line is seen.
                        // Nothing to modify before a plan exists.
                        if viewModel.mode == .workout {
                            viewModel.confirmModifications(applyTo: todayViewModel)
                        } else {
                            viewModel.rejectModifications()
                        }
                    },
                    onCancel: { viewModel.rejectModifications() }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - System Banner

    private var systemBanner: some View {
        Text(viewModel.mode == .planning ? "Tell your coach what you want, then build the plan" : "Chat with your coach about this session")
            .font(AppTheme.caveat(12))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceElevated)
    }

    // MARK: - Goals

    /// Active goals, collapsed by default; each can be dropped.
    @ViewBuilder
    private var goalsSection: some View {
        if !viewModel.activeGoals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation { showGoals.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                        Text("Goals (\(viewModel.activeGoals.count))")
                            .font(AppTheme.caveat(13, weight: .bold))
                        Spacer()
                        Image(systemName: showGoals ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.goals.toggle")

                if showGoals {
                    ForEach(viewModel.activeGoals) { goal in
                        HStack {
                            Text(goal.summary)
                                .font(AppTheme.caveat(14))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer(minLength: 8)
                            Button("Drop") { viewModel.dropGoal(id: goal.id) }
                                .font(AppTheme.caveat(14, weight: .bold))
                                .foregroundStyle(AppTheme.warning)
                                .accessibilityIdentifier("coach.goal.drop.\(goal.exerciseName)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceElevated)
        }
    }

    /// "Save goal" confirmation for a goal the athlete agreed to in chat.
    private func goalCard(_ goal: CoachGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save this goal?")
                .font(AppTheme.caveat(12))
                .foregroundStyle(AppTheme.textSecondary)
            Text(goal.summary)
                .font(AppTheme.caveat(17, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("coach.goalCard.summary")
            ForEach(Array(goal.steps.prefix(6))) { step in
                Text("• " + Self.stepLine(step))
                    .font(AppTheme.caveat(13))
                    .foregroundStyle(step.attempt ? AppTheme.accent : AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Not now") { viewModel.dismissPendingGoal() }
                    .buttonStyle(WaxSealButtonStyle(isSecondary: true))
                    .accessibilityIdentifier("coach.goalCard.dismiss")
                Button("Save goal") { viewModel.saveGoal() }
                    .buttonStyle(WaxSealButtonStyle())
                    .accessibilityIdentifier("coach.goalCard.save")
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.goalCard")
    }

    /// "Nov 10: Warm up 135x5" (date only when the coach gave one).
    static func stepLine(_ step: CoachGoalStep) -> String {
        guard let day = CoachGoal.parseDay(step.date) else { return step.text }
        return "\(day.formatted(.dateTime.month(.abbreviated).day())): \(step.text)"
    }

    // MARK: - Build plan (planning mode)

    @ViewBuilder
    private var planBar: some View {
        if viewModel.mode == .planning, let onBuildPlan {
            VStack(spacing: 6) {
                if !canBuildPlan {
                    Text("Pick a workout type on the setup screen first.")
                        .font(AppTheme.caveat(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Button {
                    let notes = viewModel.agreedPlanNotes()
                    dismiss()
                    onBuildPlan(notes)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Build today's plan")
                    }
                }
                .buttonStyle(WaxSealButtonStyle())
                .disabled(!canBuildPlan || viewModel.isLoading)
                .opacity(canBuildPlan ? 1 : 0.55)
                .accessibilityIdentifier("coach.buildPlan")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
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

                    if viewModel.canRetry && !viewModel.isLoading {
                        Button {
                            viewModel.retryLastMessage()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(AppTheme.playfairItalic(14, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .accessibilityIdentifier("chatRetryButton")
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

    @FocusState private var inputFocused: Bool

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask your coach...", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .accessibilityIdentifier("chatInputField")
                .textFieldStyle(.plain)
                .font(AppTheme.caveat(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .foregroundStyle(AppTheme.textPrimary)

            if inputFocused {
                Button {
                    inputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title3)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(minHeight: 36)
                }
                .accessibilityLabel("Dismiss keyboard")
                .accessibilityIdentifier("chatDismissKeyboard")
            }

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
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSendButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }
}
