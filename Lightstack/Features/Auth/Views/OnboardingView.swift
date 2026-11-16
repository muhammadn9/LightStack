import SwiftUI
import os

/// Three-step first-run setup, every step skippable:
/// 1. Profile stats (age, weight, height, training age, goals)
/// 2. Split day setup with one-tap presets or your own days
/// 3. Equipment picker
struct OnboardingView: View {
    private let logger = Logger(subsystem: "org.lightstack.app", category: "OnboardingView")

    @EnvironmentObject var environment: AppEnvironment
    @State private var currentStep = 0

    // Step 1: Profile
    @State private var displayName = ""
    @State private var age = ""
    @State private var weightLbs = ""
    @State private var heightFeet = ""
    @State private var heightInchesPartial = ""
    @State private var trainingAgeMonths = ""
    @State private var selectedGoals: Set<String> = []

    // Step 2: Split Days
    @State private var splitDays: [String] = []
    @State private var newDayLabel = ""
    @State private var isCustomSplit = false

    // Step 3: Equipment
    @State private var selectedEquipment: [String: Bool] = [:]
    @State private var customEquipment = ""

    // Finishing re-checks the cloud for an existing profile first.
    @State private var isFinishing = false
    @State private var finishError: String?

    private let goalOptions = [
        "Build Muscle", "Get Stronger", "Lose Fat",
        "Improve Endurance", "Stay Healthy"
    ]

    private let splitPresets: [SplitPreset] = [
        SplitPreset(id: "ppl", name: "Push / Pull / Legs", days: ["Push", "Pull", "Legs"]),
        SplitPreset(id: "upperLower", name: "Upper / Lower", days: ["Upper", "Lower"]),
        SplitPreset(id: "bodyPart", name: "Body-part split",
                    days: ["Chest", "Back", "Shoulders", "Arms", "Legs"]),
        SplitPreset(id: "fullBody", name: "Full body", days: ["Full Body A", "Full Body B"])
    ]

    /// Used when the split step is skipped or left empty.
    private let defaultSplitDays = ["Push", "Pull", "Legs"]

    private struct SplitPreset: Identifiable {
        let id: String
        let name: String
        let days: [String]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch currentStep {
                case 0: profileStepView
                case 1: splitDayStepView
                default: equipmentStepView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            bottomBar
        }
        .background(AppTheme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: currentStep)
        .onAppear {
            if displayName.isEmpty, let name = environment.authService.currentUser()?.displayName {
                displayName = name
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Back") { currentStep -= 1 }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 60, minHeight: 44, alignment: .leading)
                .opacity(currentStep > 0 ? 1 : 0)
                .disabled(currentStep == 0)
                .accessibilityIdentifier("onboarding.back")
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? AppTheme.accent : AppTheme.border)
                        .frame(width: 28, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentStep + 1) of 3")
            .accessibilityIdentifier("onboarding.progress")
            Spacer()
            Button("Skip") { skipStep() }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
                .disabled(isFinishing)
                .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let finishError {
                Text(finishError)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.destructive)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding.finishError")
            }
            if currentStep < 2 {
                primaryButton("Next", id: "onboarding.next") { currentStep += 1 }
            } else {
                Button {
                    Task { await completeOnboarding() }
                } label: {
                    Group {
                        if isFinishing {
                            ProgressView().tint(AppTheme.onAccent)
                        } else {
                            Text("Finish")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isFinishing)
                .accessibilityIdentifier("onboarding.finishButton")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func primaryButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func skipStep() {
        if currentStep < 2 {
            currentStep += 1
        } else {
            Task { await completeOnboarding() }
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold()).foregroundStyle(AppTheme.textPrimary)
            Text(subtitle).font(.body).foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 1: Profile

    private var profileStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader("About you", "Helps the coach start from your numbers. Everything is optional.")

                card {
                    field("Name", text: $displayName, keyboard: .default, id: "onboarding.name")
                    HStack(spacing: 12) {
                        field("Age", text: $age, keyboard: .numberPad, id: "onboarding.age")
                        field("Weight (lbs)", text: $weightLbs, keyboard: .decimalPad, id: "onboarding.weight")
                    }
                    HStack(spacing: 12) {
                        field("Height (ft)", text: $heightFeet, keyboard: .numberPad, id: "onboarding.heightFeet")
                        field("Height (in)", text: $heightInchesPartial, keyboard: .numberPad, id: "onboarding.heightInches")
                    }
                    field("Training (months)", text: $trainingAgeMonths, keyboard: .numberPad, id: "onboarding.training")
                }

                Text("Goals").font(.headline).foregroundStyle(AppTheme.textPrimary)
                FlowLayout(spacing: 8) {
                    ForEach(goalOptions, id: \.self) { goalChip($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func goalChip(_ goal: String) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button(action: { toggleGoal(goal) }) {
            Text(goal)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isSelected ? AppTheme.accent : AppTheme.surface, in: Capsule())
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.textPrimary)
                .overlay(Capsule().stroke(isSelected ? Color.clear : AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.goal.\(goal)")
    }

    private func toggleGoal(_ goal: String) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }

    // MARK: - Step 2: Split Days

    private var splitDayStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeader("How do you split your week?",
                           "Pick one to start. You can rename or add days any time.")

                VStack(spacing: 10) {
                    ForEach(splitPresets) { preset in
                        presetCard(preset)
                    }
                    makeMyOwnCard
                }

                if isCustomSplit {
                    customSplitEditor
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func presetCard(_ preset: SplitPreset) -> some View {
        let isActive = !isCustomSplit && splitDays == preset.days
        return Button {
            isCustomSplit = false
            splitDays = preset.days
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                Text(preset.days.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? AppTheme.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.preset.\(preset.id)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var makeMyOwnCard: some View {
        Button {
            if !isCustomSplit { splitDays = [] }
            isCustomSplit = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make my own").font(.headline).foregroundStyle(AppTheme.accent)
                Text("Name your own training days")
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(isCustomSplit ? AppTheme.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.preset.custom")
        .accessibilityAddTraits(isCustomSplit ? .isSelected : [])
    }

    private var customSplitEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !splitDays.isEmpty {
                Text("Your days").font(.headline).foregroundStyle(AppTheme.textPrimary)
                ForEach(Array(splitDays.enumerated()), id: \.offset) { index, day in
                    HStack {
                        Text(day).font(.body).foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Button { splitDays.remove(at: index) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Remove \(day)")
                        .accessibilityIdentifier("onboarding.day.remove.\(index)")
                    }
                    .padding(.leading, 16)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            HStack(spacing: 8) {
                TextField("Add a day (e.g. Heavy Pull)", text: $newDayLabel)
                    .font(.body)
                    .submitLabel(.done)
                    .onSubmit(addCustomDay)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("onboarding.day.field")
                Button(action: addCustomDay) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(newDayLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add day")
                .accessibilityIdentifier("onboarding.day.add")
            }
        }
    }

    private func addCustomDay() {
        let trimmed = newDayLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        splitDays.append(trimmed)
        newDayLabel = ""
    }

    // MARK: - Step 3: Equipment

    private var equipmentStepView: some View {
        EquipmentPickerView(
            selectedEquipment: $selectedEquipment,
            customEquipment: $customEquipment
        )
    }

    // MARK: - Finish

    private func completeOnboarding() async {
        guard let userId = environment.authService.currentUser()?.userId else { return }

        let profile = UserProfile.create(
            userId: userId,
            displayName: displayName.isEmpty ? nil : displayName,
            age: Int(age),
            heightInches: Double((Int(heightFeet) ?? 0) * 12 + (Int(heightInchesPartial) ?? 0)),
            weightLbs: Double(weightLbs),
            trainingAgeMonths: Int(trainingAgeMonths),
            primaryGoals: Array(selectedGoals),
            splitDays: splitDays.isEmpty ? defaultSplitDays : splitDays,
            avoidExercises: [],
            equipment: selectedEquipment,
            customEquipment: customEquipment.isEmpty ? nil : customEquipment,
            notesToCoach: nil
        )

        logger.debug("Saving profile with split days: \(splitDays.isEmpty ? defaultSplitDays : splitDays)")
        isFinishing = true
        finishError = nil
        // Saves the new profile only if the account has none in the cloud; otherwise the
        // existing one is adopted (a new device must never overwrite it).
        let result = await environment.finishOnboarding(with: profile)
        isFinishing = false
        if result == .couldNotVerify {
            finishError = "Couldn't check your account. Check your connection and tap Finish again."
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType,
                       id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(AppTheme.textSecondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .font(.body)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .foregroundStyle(AppTheme.textPrimary)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(id)
        }
    }
}
