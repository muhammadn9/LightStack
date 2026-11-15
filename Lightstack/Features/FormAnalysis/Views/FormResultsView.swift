import SwiftUI

/// Results of one recorded set: replay with skeleton, summary, AI coach feedback, rep strip and measurements.
struct FormResultsView: View {

    @StateObject private var model: FormResultsViewModel
    let onRecordAgain: () -> Void
    let onClose: () -> Void
    @State private var showingShareData = false

    init(result: FormSessionResult, feedbackProvider: FormFeedbackProviding,
         onRecordAgain: @escaping () -> Void, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: FormResultsViewModel(result: result, provider: feedbackProvider))
        self.onRecordAgain = onRecordAgain
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    FormReplayView(replay: model.replay,
                                   highlighted: FormKeyFrameSheet.highlightedJoints(for: model.analysis.profile),
                                   screenHeight: geo.size.height * 0.34)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            FormSummaryRow(repDisplay: model.repDisplay, score: model.analysis.score,
                                           status: model.analysis.detection.status)
                            FormCoachSection(feedback: model.feedback, isLoading: model.isLoadingFeedback,
                                             failure: model.failureReason,
                                             onSelectFix: { model.seek(to: $0) },
                                             canSeek: { model.seekTime(for: $0) != nil },
                                             onRetry: { model.retryFeedback() })
                            if model.hasReps {
                                FormRepStrip(reps: model.analysis.reps) { model.seek(toRepStart: $0) }
                            }
                            FormMeasuredSection(findings: model.sortedFindings,
                                                untrackable: model.untrackableFinding,
                                                cameraTip: model.analysis.profile.cameraTip,
                                                onSelect: { model.seek(to: $0) },
                                                onRecordAgain: onRecordAgain)
                            Button { showingShareData = true } label: {
                                Label("Something off? Share tracking data", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                            }
                            .accessibilityIdentifier("formResults.shareData")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(model.result.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            model.replay.play()
            model.loadFeedbackIfNeeded()
        }
        .onDisappear { model.teardown() }
        .sheet(isPresented: $showingShareData) {
            FormShareDataSheet(model: model)
                .presentationDetents([.medium])
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: onRecordAgain) {
                Text("Record again")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(AppTheme.surfaceElevated, in: Capsule())
            }
            .accessibilityIdentifier("formResults.recordAgain")
            Button(action: onClose) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(AppTheme.accent, in: Capsule())
            }
            .accessibilityIdentifier("formResults.done")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
