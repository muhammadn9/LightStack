import SwiftUI

/// Today home: greeting, week strip, this week's muscle sets, the workout split, a compact settings card and the start buttons.
struct WorkoutSetupView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: WorkoutSetupViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    /// When provided, "Talk to the coach" opens the chat before any plan exists.
    var chatViewModel: CoachChatViewModel? = nil
    @State private var showCoachChat = false
    @State private var showManualEntry = false
    @State private var lastInfo: TodayViewModel.LastSessionInfo?
    @State private var weekly = WeeklyMuscleSummary()
    @State private var snapshot = ProgressSnapshot()
    @State private var selectedDay: SelectedDay?
    @State private var manualEntryDate: Date?

    private struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private var userId: UUID? { environment.authService.currentUser()?.userId }
    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var hasWorkoutToday: Bool { snapshot.workoutDays.contains(todayStart) }
    private var isRestToday: Bool { snapshot.restDays.contains(todayStart) }

    private func refreshSnapshot() {
        guard let userId else { return }
        snapshot = ProgressStatsService(localStorage: environment.localStorageService).snapshot(userId: userId)
        weekly = WeeklyMuscleService(workoutRepository: environment.workoutRepository).summary(userId: userId)
    }

    private func refreshLastSession() {
        let type = viewModel.selectedWorkoutType
        lastInfo = type.isEmpty ? nil : todayViewModel.lastSessionInfo(ofType: type)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let first = environment.authService.currentUser()?.displayName?
            .split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    private var dateText: String { DateFormatter.weekdayMonthDay.string(from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                WeekStripView(workoutDays: snapshot.workoutDays, restDays: snapshot.restDays) { date in
                    selectedDay = SelectedDay(date: date)
                }

                ThisWeekCard(summary: weekly)

                splitCard

                settingsCard

                buttons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .statusBarBackdrop()
        .tabBarBackdrop()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.selectedWorkoutType) { _, _ in refreshLastSession() }
        .onAppear {
            refreshSnapshot()
            if let userId = environment.authService.currentUser()?.userId {
                viewModel.loadSplitDays(userId: userId)
                todayViewModel.setUserId(userId)
                viewModel.historyWorkoutNames = todayViewModel.historyWorkoutNames(excluding: viewModel.splitDays)
            }
            refreshLastSession()
        }
        .sheet(item: $selectedDay, onDismiss: {
            refreshSnapshot()
            if manualEntryDate != nil { showManualEntry = true }
        }) { day in
            if let userId {
                DaySheetView(date: day.date, userId: userId, onChange: refreshSnapshot) { date in
                    manualEntryDate = date
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showCoachChat) {
            if let chatViewModel {
                CoachChatView(
                    viewModel: chatViewModel,
                    todayViewModel: todayViewModel,
                    onBuildPlan: { notes in buildPlan(withChatNotes: notes) },
                    canBuildPlan: !viewModel.selectedWorkoutType.isEmpty
                )
            }
        }
        .sheet(isPresented: $showManualEntry, onDismiss: { manualEntryDate = nil }) {
            if let userId = environment.authService.currentUser()?.userId {
                ManualWorkoutEntryView(todayViewModel: todayViewModel, userId: userId, logDate: manualEntryDate)
                    .keyboardDoneButton()
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
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
            Spacer(minLength: 8)
            SideSwitchButton()
            if let chatViewModel, let userId {
                Button {
                    chatViewModel.configurePlanning(userId: userId)
                    showCoachChat = true
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk to the coach")
                .accessibilityIdentifier("talkToCoachButton")
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Workout split

    private var splitCard: some View {
        SetupCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workout split")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("splitHeader")
                if viewModel.chips.isEmpty {
                    Text("No split days configured. Add them in your profile.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.chips, id: \.self) { name in
                            SetupChip(
                                label: name,
                                isSelected: viewModel.selectedWorkoutType.caseInsensitiveCompare(name) == .orderedSame,
                                action: { viewModel.selectedWorkoutType = name }
                            )
                        }
                    }
                }
                if let lastInfo, !viewModel.selectedWorkoutType.isEmpty {
                    Text("Last \(viewModel.selectedWorkoutType): \(lastInfo.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \u{00B7} \(lastInfo.exerciseCount) \(lastInfo.exerciseCount == 1 ? "exercise" : "exercises"). The coach builds on it.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("setup.lastSession")
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        SetupCard(padding: 0) {
            VStack(spacing: 0) {
                settingsRow(.energy, title: "Energy", value: viewModel.energySummary, id: "setup.row.energy") {
                    energyControl
                }
                Divider().padding(.leading, 16)
                settingsRow(.time, title: "Time", value: viewModel.timeSummary, id: "setup.row.time") {
                    timeControl
                }
                Divider().padding(.leading, 16)
                settingsRow(.notes, title: "Notes and focus", value: viewModel.notesSummary, id: "setup.moreOptions") {
                    notesControl
                }
            }
        }
    }

    private func settingsRow<Control: View>(
        _ row: WorkoutSetupViewModel.SettingsRow, title: String, value: String, id: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        let isOpen = viewModel.expandedRow == row
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.toggleRow(row) }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
            .accessibilityValue(isOpen ? "expanded, \(value)" : value)

            if isOpen {
                control()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private var energyControl: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { i in
                let filled = i <= viewModel.energyDots
                Button(action: { viewModel.energyLevel = WorkoutSetupViewModel.energyLevel(forDots: i) }) {
                    Circle()
                        .fill(filled ? AppTheme.accent : AppTheme.surfaceElevated)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("energyDot.\(i)")
                .accessibilityLabel("Energy \(i) of 5")
                .accessibilityValue(filled ? "selected" : "not selected")
            }
            Text("\(viewModel.energyDots) / 5")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("energyLabel")
        }
    }

    private var timeControl: some View {
        HStack(spacing: 10) {
            Text("\(viewModel.timeAvailable)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("timeValue")
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

    private var notesControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes for the coach")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("Feeling strong today, focus on chest...",
                          text: $viewModel.additionalNotes,
                          axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .lineLimit(2...5)
                    .accessibilityIdentifier("setup.notes")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Constraints")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("e.g. incline smith taken, fasted, knee tweak",
                          text: $viewModel.constraints, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .lineLimit(1...3)
                    .accessibilityIdentifier("setup.constraints")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Picker("Focus", selection: Binding(
                    get: { viewModel.focus },
                    set: { viewModel.chooseFocus($0) }
                )) {
                    ForEach(CoachFocus.allCases, id: \.self) { focus in
                        Text(WorkoutSetupViewModel.focusTitle(focus)).tag(focus)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup.focus")
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 12) {
            let type = viewModel.selectedWorkoutType
            Button(action: submitWorkout) {
                Text(type.isEmpty ? "Build my workout" : "Build my \(type) workout")
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(SetupPrimaryButtonStyle())
            .accessibilityIdentifier("generateButton")
            .disabled(type.isEmpty)
            .opacity(type.isEmpty ? 0.55 : 1)

            HStack(spacing: 12) {
                Button { todayViewModel.startFreestyle() } label: {
                    Text("Freestyle")
                }
                .buttonStyle(SetupSecondaryButtonStyle(tint: AppTheme.accent))
                .accessibilityIdentifier("freestyleButton")

                if !hasWorkoutToday || isRestToday {
                    restTodayButton
                }
            }
        }
        .padding(.top, 4)
    }

    private var restTodayButton: some View {
        Button {
            guard let userId else { return }
            if isRestToday {
                environment.restDayRepository.removeRestDay(userId: userId, date: Date())
            } else {
                environment.restDayRepository.addRestDay(userId: userId, date: Date())
            }
            refreshSnapshot()
        } label: {
            Text(isRestToday ? "Rest day \u{2713} \u{00B7} Undo" : "Rest day")
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .buttonStyle(SetupSecondaryButtonStyle(tint: AppTheme.textPrimary))
        .accessibilityIdentifier("restTodayButton")
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

    /// The plan request with what was agreed in the chat as the session notes (at most 300 characters).
    private func buildPlan(withChatNotes notes: String) {
        let agreed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agreed.isEmpty {
            let typed = viewModel.additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let merged = typed.isEmpty || agreed.contains(typed) ? agreed : "\(typed); \(agreed)"
            viewModel.additionalNotes = CoachChatViewModel.truncated(merged, CoachChatViewModel.planNotesLimit)
        }
        showCoachChat = false
        submitWorkout()
    }

    private func submitWorkout() {
        guard let params = viewModel.validateAndSubmit() else { return }
        todayViewModel.generatePlan(
            workoutType: params.workoutType,
            time: params.time,
            energy: params.energy,
            notes: params.notes,
            constraints: params.constraints,
            focus: params.focus
        )
    }
}

// MARK: - Components

/// White rounded card (dark surface in dark mode).
private struct SetupCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}

/// "This week": workouts and sets so far, then sets per muscle group (worked groups first).
private struct ThisWeekCard: View {
    let summary: WeeklyMuscleSummary

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        SetupCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer(minLength: 8)
                    Text(summary.headline)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("thisWeek.headline")
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(summary.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AppTheme.surfaceElevated)
                                    Capsule().fill(AppTheme.accent)
                                        .frame(width: proxy.size.width * fill(entry.sets))
                                }
                            }
                            .frame(height: 6)
                            Text(entry.group.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(entry.sets > 0 ? "\(entry.sets) \(entry.sets == 1 ? "set" : "sets")" : "not yet")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(entry.group.rawValue), \(entry.sets > 0 ? "\(entry.sets) sets" : "not yet")")
                        .accessibilityIdentifier("thisWeek.group.\(entry.group.rawValue)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thisWeek.card")
    }

    /// Bar fill: ten sets of a group in a week fills the bar; any work shows a sliver.
    private func fill(_ sets: Int) -> CGFloat {
        sets <= 0 ? 0 : max(0.12, min(1, CGFloat(sets) / 10))
    }
}

/// Capsule chip for the workout split.
private struct SetupChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.textPrimary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityIdentifier("chip.\(label)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Big accent pill.
private struct SetupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(AppTheme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AppTheme.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// White capsule used for Freestyle and Rest day.
private struct SetupSecondaryButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AppTheme.surface, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
