import SwiftUI

/// AI conversation interface for building a month plan.
/// User states their target goal and the AI generates a structured plan.
struct PlanBuilderChatView: View {
    @ObservedObject var viewModel: PlanBuilderViewModel
    var onPlanGenerated: ((MonthPlan, [PlannedSession]) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    goalCard
                    messageList

                    if viewModel.planGenerated {
                        viewPlanButton
                    }
                }
                .padding(16)
            }

            if !viewModel.planGenerated {
                bottomBar
            }
        }
        .themedBackground()
        .onChange(of: viewModel.planGenerated) { _, generated in
            if generated, let plan = viewModel.generatedPlan {
                onPlanGenerated?(plan, viewModel.generatedSessions)
            }
        }
    }

    // MARK: - Goal Card

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(AppTheme.accent)
                Text("Tell the coach your training goal")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            TextField("e.g., Build muscle, get stronger at bench press...", text: $viewModel.targetGoal, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .lineLimit(3...8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Training days per week")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 8) {
                    ForEach(2...6, id: \.self) { days in
                        Button(action: { viewModel.daysPerWeek = days }) {
                            Text("\(days)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(viewModel.daysPerWeek == days ? .white : AppTheme.textSecondary)
                                .frame(width: 44, height: 36)
                                .background(viewModel.daysPerWeek == days ? AppTheme.accent : AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Message List

    private var messageList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.messages) { message in
                MessageBubbleView(message: message)
            }

            if viewModel.isGenerating {
                HStack {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Generating your plan...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - View Plan Button

    private var viewPlanButton: some View {
        Button(action: {
            if let plan = viewModel.generatedPlan {
                onPlanGenerated?(plan, viewModel.generatedSessions)
            }
        }) {
            HStack {
                Image(systemName: "calendar")
                Text("View Your Plan")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.destructive)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Button(action: { viewModel.generatePlan() }) {
                HStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.isGenerating ? "Generating..." : "Generate Plan")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    viewModel.targetGoal.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isGenerating
                        ? AnyShapeStyle(AppTheme.surfaceElevated)
                        : AnyShapeStyle(AppTheme.accentGradient)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .disabled(viewModel.targetGoal.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isGenerating)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.background)
    }
}
