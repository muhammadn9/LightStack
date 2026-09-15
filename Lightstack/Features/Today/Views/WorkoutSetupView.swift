import SwiftUI

/// Pre-workout setup: training-log journal form style matching the Coach's Notebook mockup.
struct WorkoutSetupView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: WorkoutSetupViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @State private var showManualEntry = false

    private var todayHeader: String {
        "\(DateFormatter.weekdayMonthDay.string(from: Date())) — Training Log"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Date + heading
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayHeader)
                        .font(AppTheme.playfairItalic(13))
                        .foregroundStyle(AppTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("What are we")
                            .font(AppTheme.playfair(26, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("training today?")
                            .font(AppTheme.playfairItalic(26, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.top, 4)

                InkDivider()

                // Workout Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Type")
                        .notebookSectionHeader()
                    if viewModel.splitDays.isEmpty {
                        Text("No split days configured. Add them in your profile.")
                            .font(AppTheme.caveat(14))
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

                // Energy Level (5-dot scale)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Energy Level")
                        .notebookSectionHeader()
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Button(action: { viewModel.energyLevel = i * 2 }) {
                                Circle()
                                    .fill(i * 2 <= viewModel.energyLevel ? AppTheme.accent : Color.clear)
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        let displayDots = min(5, max(1, (viewModel.energyLevel + 1) / 2))
                        Text("\(displayDots) / 5")
                            .font(AppTheme.caveat(13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.leading, 4)
                    }
                }

                // Time Available — stepper style
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Available")
                        .notebookSectionHeader()
                    HStack(spacing: 10) {
                        Text("\(viewModel.timeAvailable)")
                            .font(AppTheme.playfair(26, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("minutes")
                            .font(AppTheme.caveat(13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 4)
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: { if viewModel.timeAvailable > 15 { viewModel.timeAvailable -= 15 } }) {
                                Text("−")
                                    .font(AppTheme.caveat(18, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(AppTheme.border, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button(action: { if viewModel.timeAvailable < 120 { viewModel.timeAvailable += 15 } }) {
                                Text("+")
                                    .font(AppTheme.caveat(18, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(AppTheme.border, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes for Coach")
                        .notebookSectionHeader()
                    TextField("Feeling strong today, focus on chest...",
                              text: $viewModel.additionalNotes,
                              axis: .vertical)
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
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
                            Text("✦")
                            Text("Generate My Workout")
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
                .padding(.top, 4)
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
