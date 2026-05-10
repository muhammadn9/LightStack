import SwiftUI

enum TodayDemoState: String, CaseIterable, Identifiable {
    case setup  = "Setup"
    case active = "Active"
    var id: String { rawValue }
}

struct MockTodayView: View {
    @State private var demoState: TodayDemoState = .setup

    var body: some View {
        VStack(spacing: 0) {
            Picker("Demo State", selection: $demoState) {
                ForEach(TodayDemoState.allCases) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .padding(ModernTheme.spacingM)
            .background(Color(.systemGroupedBackground))

            switch demoState {
            case .setup:
                SetupSection()
            case .active:
                ActiveWorkoutSection()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Setup Section

private struct SetupSection: View {
    @State private var selectedFocus: String = "Push"
    @State private var energy: Int = 3
    @State private var selectedTime: String = "45 min"

    private let focusOptions = ["Push", "Pull", "Legs", "Upper", "Lower", "Custom"]
    private let timeOptions  = ["30 min", "45 min", "60 min"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ModernTheme.spacingM) {
                    heroCard
                    workoutTypeCard
                    energyCard
                    timeCard

                    VStack(spacing: ModernTheme.spacingS) {
                        Button("Generate Workout") {}
                            .buttonStyle(ModernPrimaryButtonStyle())

                        Button("Manual Entry") {}
                            .buttonStyle(ModernSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, ModernTheme.spacingM)
                .padding(.bottom, ModernTheme.spacingXL)
            }
            .modernScreenBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: ModernTheme.spacingXS) {
                        Image(systemName: "flame.fill")
                        Text("\(MockData.userStreak)")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(ModernTheme.accent)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: ModernTheme.spacingS) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44))
                .foregroundStyle(ModernTheme.accent)

            Text("Ready to train?")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("Tell your coach what you want to work today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .modernCard()
    }

    private var workoutTypeCard: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingS) {
            Text("Today's focus")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: ModernTheme.spacingS
            ) {
                ForEach(focusOptions, id: \.self) { option in
                    Button {
                        selectedFocus = option
                    } label: {
                        Text(option)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selectedFocus == option ? .white : ModernTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedFocus == option
                                    ? ModernTheme.accent
                                    : ModernTheme.accent.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernCard()
    }

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingS) {
            Text("Energy")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: ModernTheme.spacingS) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        energy = level
                    } label: {
                        ZStack {
                            Circle()
                                .fill(energy == level ? ModernTheme.accent : Color.clear)
                            Circle()
                                .strokeBorder(
                                    energy == level ? ModernTheme.accent : Color(.separator),
                                    lineWidth: 1.5
                                )
                            Text("\(level)")
                                .font(.subheadline.bold())
                                .foregroundStyle(energy == level ? .white : .secondary)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernCard()
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingS) {
            Text("Time")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: ModernTheme.spacingS) {
                ForEach(timeOptions, id: \.self) { option in
                    Button {
                        selectedTime = option
                    } label: {
                        Text(option)
                            .font(.subheadline.bold())
                            .foregroundStyle(selectedTime == option ? .white : ModernTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                selectedTime == option
                                    ? ModernTheme.accent
                                    : ModernTheme.accent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: ModernTheme.radiusS, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernCard()
    }
}

// MARK: - Active Workout Section

private struct ActiveWorkoutSection: View {
    @State private var weightInput: String = ""
    @State private var repsInput: String  = ""
    @State private var rirInput: String   = ""
    @State private var restActive: Bool   = true
    @State private var showCoach: Bool    = false

    private var currentExercise: MockExercise? { MockData.todayExercises.first }
    private var upNextExercises: [MockExercise] {
        Array(MockData.todayExercises.dropFirst().prefix(2))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: ModernTheme.spacingM) {
                        if let exercise = currentExercise {
                            currentExerciseCard(exercise)
                        }

                        upNextSection
                    }
                    .padding(.horizontal, ModernTheme.spacingM)
                    .padding(.bottom, 96)
                }
                .modernScreenBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(MockData.todayWorkoutType)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("24:18")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(ModernTheme.accent)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                        } label: {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(ModernTheme.accent)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showCoach = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(ModernTheme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(16)
                .padding(.bottom, 72)
            }
            .sheet(isPresented: $showCoach) {
                Text("Coach Sheet — placeholder")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding()
            }

            finishButton
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func currentExerciseCard(_ exercise: MockExercise) -> some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingM) {
            VStack(alignment: .leading, spacing: ModernTheme.spacingXS) {
                Text(exercise.name)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                HStack(spacing: ModernTheme.spacingS) {
                    ModernChip(label: exercise.muscleGroup)

                    Text("set \(MockData.activeLoggedSets.count + 1) of \(exercise.targetSets)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: ModernTheme.spacingXS) {
                ForEach(MockData.activeLoggedSets) { set in
                    loggedSetRow(set)
                }
            }

            inputRow

            if restActive {
                restTimerBanner
            }
        }
        .modernCard()
    }

    private func loggedSetRow(_ set: MockSet) -> some View {
        HStack(spacing: ModernTheme.spacingS) {
            ZStack {
                Circle()
                    .fill(ModernTheme.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(set.setNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(ModernTheme.accent)
            }

            Text("\(Int(set.weightLbs)) lbs × \(set.reps) reps")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var inputRow: some View {
        HStack(spacing: ModernTheme.spacingS) {
            inputField(placeholder: "lbs",  text: $weightInput)
            inputField(placeholder: "reps", text: $repsInput)
            inputField(placeholder: "RIR",  text: $rirInput)

            Button {
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(ModernTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func inputField(placeholder: String, text: Binding<String>) -> some View {
        TextField("0", text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: ModernTheme.radiusS, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                Text(placeholder)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 14)
            }
            .padding(.bottom, 16)
    }

    private var restTimerBanner: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingXS) {
            Text("Rest 1:24")
                .font(.caption.bold())
                .foregroundStyle(ModernTheme.accent)
                .padding(.horizontal, ModernTheme.spacingS)
                .padding(.vertical, ModernTheme.spacingXS)
                .background(ModernTheme.accent.opacity(0.12), in: Capsule())

            ProgressView(value: 0.6)
                .tint(ModernTheme.accent)
        }
    }

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingS) {
            Text("Up next")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, ModernTheme.spacingXS)

            VStack(spacing: ModernTheme.spacingXS) {
                ForEach(upNextExercises) { exercise in
                    upNextRow(exercise)
                }
            }
        }
    }

    private func upNextRow(_ exercise: MockExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: ModernTheme.spacingXS) {
                Text(exercise.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("\(exercise.targetSets) sets · \(exercise.targetReps) reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ModernChip(label: exercise.muscleGroup)
        }
        .modernCardFilled(padding: ModernTheme.spacingS)
    }

    private var finishButton: some View {
        Button("Finish Workout") {}
            .buttonStyle(ModernPrimaryButtonStyle())
            .padding(.horizontal, ModernTheme.spacingM)
            .padding(.bottom, ModernTheme.spacingL)
            .background(.regularMaterial)
    }
}

// MARK: - Previews

#Preview("Light") {
    MockTodayView()
}

#Preview("Dark") {
    MockTodayView()
        .preferredColorScheme(.dark)
}
