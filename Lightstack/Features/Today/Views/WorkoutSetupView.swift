import SwiftUI

/// Pre-workout setup: day label selector, time available, energy level picker.
struct WorkoutSetupView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: WorkoutSetupViewModel
    @ObservedObject var todayViewModel: TodayViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                splitDaySection
                timeSection
                energySection
                notesSection
                generateButton
            }
            .padding(20)
        }
        .onAppear {
            if let userId = environment.authService.currentUser()?.userId {
                viewModel.loadSplitDays(userId: userId)
                todayViewModel.setUserId(userId)
            }
        }
    }

    // MARK: - Split Day Selection

    private var splitDaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout Type")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if viewModel.splitDays.isEmpty {
                Text("No split days configured. Add them in your profile.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.splitDays, id: \.self) { day in
                            splitDayChip(day)
                        }
                    }
                }
            }
        }
    }

    private func splitDayChip(_ day: String) -> some View {
        let isSelected = viewModel.selectedWorkoutType == day
        return Button(action: { viewModel.selectedWorkoutType = day }) {
            Text(day)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.accent : AppTheme.surface)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : AppTheme.surfaceElevated, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Presets

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time Available")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 10) {
                ForEach(WorkoutSetupViewModel.timePresets, id: \.self) { mins in
                    timeChip(mins)
                }
            }
        }
    }

    private func timeChip(_ minutes: Int) -> some View {
        let isSelected = viewModel.timeAvailable == minutes
        return Button(action: { viewModel.timeAvailable = minutes }) {
            Text("\(minutes)m")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : AppTheme.surface)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : AppTheme.surfaceElevated, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Energy Slider

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Energy Level")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(viewModel.energyLevel)/10")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accentSecondary)
            }

            Slider(
                value: .init(
                    get: { Double(viewModel.energyLevel) },
                    set: { viewModel.energyLevel = Int($0) }
                ),
                in: 1...10,
                step: 1
            )
            .tint(AppTheme.accent)

            HStack {
                Text("Low").font(.caption).foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("High").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g. Focus on bench today, skip isolation",
                      text: $viewModel.additionalNotes,
                      axis: .vertical)
                .padding(14)
                .background(AppTheme.surface)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .lineLimit(2...4)
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button(action: submitWorkout) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Generate Workout")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 12, x: 0, y: 4)
        }
        .disabled(viewModel.selectedWorkoutType.isEmpty)
        .opacity(viewModel.selectedWorkoutType.isEmpty ? 0.6 : 1)
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
}
