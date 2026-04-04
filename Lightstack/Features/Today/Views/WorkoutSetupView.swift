import SwiftUI

/// Pre-workout setup: training-log journal form style.
struct WorkoutSetupView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: WorkoutSetupViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @State private var showManualEntry = false

    private var todayHeader: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return "\(f.string(from: Date())) — Training Log"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Date header
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayHeader)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("What are we training today?")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.top, 4)

                // Workout Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Type")
                        .notebookSectionHeader()
                    if viewModel.splitDays.isEmpty {
                        Text("No split days configured. Add them in your profile.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.splitDays, id: \.self) { day in
                                JournalChip(
                                    label: day,
                                    isSelected: viewModel.selectedWorkoutType == day,
                                    action: { viewModel.selectedWorkoutType = day }
                                )
                            }
                        }
                    }
                }

                // Time Available
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Available")
                        .notebookSectionHeader()
                    HStack(spacing: 6) {
                        ForEach(WorkoutSetupViewModel.timePresets, id: \.self) { mins in
                            JournalChip(
                                label: "\(mins)m",
                                isSelected: viewModel.timeAvailable == mins,
                                action: { viewModel.timeAvailable = mins }
                            )
                        }
                    }
                }

                // Energy Level
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Energy Level")
                            .notebookSectionHeader()
                        Spacer()
                        Text("\(viewModel.energyLevel) / 10")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }
                    InkDotRating(value: viewModel.energyLevel, max: 10) { viewModel.energyLevel = $0 }
                }

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes for Coach")
                        .notebookSectionHeader()
                    TextField("e.g. Focus on bench, skip isolation...",
                              text: $viewModel.additionalNotes,
                              axis: .vertical)
                        .font(.system(size: 14).italic())
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                .foregroundStyle(AppTheme.border)
                        )
                        .lineLimit(2...5)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { hideKeyboard() }
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                }

                // Buttons
                VStack(spacing: 10) {
                    Button(action: submitWorkout) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Generate Workout")
                        }
                    }
                    .buttonStyle(WaxSealButtonStyle(isSecondary: false))
                    .disabled(viewModel.selectedWorkoutType.isEmpty)
                    .opacity(viewModel.selectedWorkoutType.isEmpty ? 0.55 : 1)

                    Button(action: { showManualEntry = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.and.list.clipboard")
                            Text("Log Manually")
                        }
                    }
                    .buttonStyle(WaxSealButtonStyle(isSecondary: true))
                }
            }
            .padding(20)
        }
        .themedBackground()
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if let userId = environment.authService.currentUser()?.userId {
                viewModel.loadSplitDays(userId: userId)
                todayViewModel.setUserId(userId)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            if let userId = environment.authService.currentUser()?.userId {
                ManualWorkoutEntryView(todayViewModel: todayViewModel, userId: userId)
            }
        }
    }

    private func submitWorkout() {
        guard let params = viewModel.validateAndSubmit() else { return }
        todayViewModel.generatePlan(
            workoutType: params.workoutType,
            time: params.time,
            energy: params.energy,
            notes: params.notes
        )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
