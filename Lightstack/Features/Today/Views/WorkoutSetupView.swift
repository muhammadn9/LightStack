import SwiftUI

/// Today home: greeting, week strip, equipment hero, then the pre-workout setup controls.
struct WorkoutSetupView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: WorkoutSetupViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @State private var showManualEntry = false
    @State private var lastSessionMatch: Workout?
    @State private var snapshot = ProgressSnapshot()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let first = environment.authService.currentUser()?.displayName?
            .split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    private var dateText: String { DateFormatter.weekdayMonthDay.string(from: Date()) }

    private func sectionCard<Content: View>(_ title: String, titleId: String = "", @ViewBuilder _ content: @escaping () -> Content) -> some View {
        ProgressCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier(titleId)
                content()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Greeting + date
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("today.greeting")
                    Text(dateText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.top, 4)

                WeekStripView(trainedDays: snapshot.trainedWeekdays)

                EquipmentWeekCard(usage: snapshot.equipmentThisWeek)

                // Workout Type
                sectionCard("Workout Type") {
                    if viewModel.splitDays.isEmpty {
                        Text("No split days configured. Add them in your profile.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.splitDays, id: \.self) { day in
                                SetupChip(
                                    label: day,
                                    isSelected: viewModel.selectedWorkoutType == day,
                                    action: { viewModel.selectedWorkoutType = day }
                                )
                            }
                        }
                    }
                }

                if !viewModel.historyWorkoutNames.isEmpty {
                    historySection
                }

                // Energy Level (5-dot scale)
                sectionCard("Energy Level") {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { i in
                            Button(action: { viewModel.energyLevel = i * 2 }) {
                                Circle()
                                    .fill(i * 2 <= viewModel.energyLevel ? AppTheme.accent : AppTheme.surfaceElevated)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                        }
                        let displayDots = min(5, max(1, (viewModel.energyLevel + 1) / 2))
                        Text("\(displayDots) / 5")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.leading, 4)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Energy level")
                    .accessibilityValue("\(min(5, max(1, (viewModel.energyLevel + 1) / 2))) out of 5")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if viewModel.energyLevel < 10 { viewModel.energyLevel += 2 }
                        case .decrement:
                            if viewModel.energyLevel > 2 { viewModel.energyLevel -= 2 }
                        @unknown default:
                            break
                        }
                    }
                }

                // Time Available
                sectionCard("Time Available") {
                    HStack(spacing: 10) {
                        Text("\(viewModel.timeAvailable)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("minutes")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 6)
                        Spacer()
                        HStack(spacing: 10) {
                            stepperButton("minus", label: "Decrease time") {
                                if viewModel.timeAvailable > 15 { viewModel.timeAvailable -= 15 }
                            }
                            stepperButton("plus", label: "Increase time") {
                                if viewModel.timeAvailable < 120 { viewModel.timeAvailable += 15 }
                            }
                        }
                    }
                }

                // Notes
                sectionCard("Notes for Coach") {
                    TextField("Feeling strong today, focus on chest...",
                              text: $viewModel.additionalNotes,
                              axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .lineLimit(2...5)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: submitWorkout) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Generate My Workout")
                        }
                    }
                    .buttonStyle(SetupPrimaryButtonStyle())
                    .accessibilityIdentifier("generateButton")
                    .disabled(viewModel.selectedWorkoutType.isEmpty)
                    .opacity(viewModel.selectedWorkoutType.isEmpty ? 0.55 : 1)

                    Button(action: { showManualEntry = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.and.list.clipboard")
                            Text("Log Manually")
                        }
                    }
                    .buttonStyle(SetupSecondaryButtonStyle())
                    .accessibilityIdentifier("logManuallyButton")

                    if let last = lastSessionMatch, !viewModel.selectedWorkoutType.isEmpty {
                        Button(action: { todayViewModel.repeatLastSession(ofType: viewModel.selectedWorkoutType) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Repeat last \(viewModel.selectedWorkoutType) · \(last.date.formatted(.dateTime.month(.abbreviated).day()))")
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(SetupSecondaryButtonStyle())
                        .accessibilityIdentifier("repeatLastButton")
                        .accessibilityHint("Starts with the same exercises as last time, no AI coaching")
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.selectedWorkoutType) { _, newType in
            lastSessionMatch = newType.isEmpty ? nil : todayViewModel.lastSession(ofType: newType)
        }
        .onAppear {
            if let userId = environment.authService.currentUser()?.userId {
                snapshot = ProgressStatsService(localStorage: environment.localStorageService)
                    .snapshot(userId: userId)
                viewModel.loadSplitDays(userId: userId)
                todayViewModel.setUserId(userId)
                viewModel.historyWorkoutNames = todayViewModel.historyWorkoutNames(excluding: viewModel.splitDays)
            }
            let type = viewModel.selectedWorkoutType
            lastSessionMatch = type.isEmpty ? nil : todayViewModel.lastSession(ofType: type)
        }
        .sheet(isPresented: $showManualEntry) {
            if let userId = environment.authService.currentUser()?.userId {
                ManualWorkoutEntryView(todayViewModel: todayViewModel, userId: userId)
                    .keyboardDoneButton()
            }
        }
    }

    /// Past workout names outside the split. Picking one starts a fresh workout from
    /// that workout's latest exercises, with no AI generation.
    private var historySection: some View {
        sectionCard("From history", titleId: "fromHistoryHeader") {
            FlowLayout(spacing: 8) {
                ForEach(viewModel.visibleHistoryNames, id: \.self) { name in
                    SetupChip(
                        label: name,
                        isSelected: false,
                        action: { todayViewModel.repeatLastSession(ofType: name) }
                    )
                }
                if viewModel.hasHiddenHistory {
                    Button(viewModel.showAllHistory ? "Show less" : "Show all (\(viewModel.historyWorkoutNames.count))") {
                        withAnimation { viewModel.showAllHistory.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("historyShowAllButton")
                }
            }
            Text("Starts with the same exercises as last time, no AI coaching.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func stepperButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppTheme.surfaceElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

// MARK: - Styles

/// Capsule chip for workout types and history names.
private struct SetupChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? ProgressStyle.onAccent : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityIdentifier("chip.\(label)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Big accent pill with dark text.
private struct SetupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(ProgressStyle.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(AppTheme.accent, in: Capsule())
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 14, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SetupSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppTheme.accent.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
