import SwiftUI

/// Three-step onboarding flow with purple radiant dark theme:
/// 1. Profile stats (age, weight, height, training age, goals)
/// 2. Split day setup with preset suggestions
/// 3. Equipment picker
struct OnboardingView: View {
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

    // Step 3: Equipment
    @State private var selectedEquipment: [String: Bool] = [:]

    private let goalOptions = [
        "Build Muscle", "Get Stronger", "Lose Fat",
        "Improve Endurance", "Stay Healthy"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                VStack {
                    stepIndicator
                    TabView(selection: $currentStep) {
                        profileStepView.tag(0)
                        splitDayStepView.tag(1)
                        equipmentStepView.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)
                    navigationButtons
                }
            }
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= currentStep
                          ? AppTheme.accentGradient
                          : LinearGradient(colors: [AppTheme.surfaceElevated], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Step 1: Profile

    private var profileStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("About You")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)

                themedField("Display Name", text: $displayName)

                HStack(spacing: 12) {
                    labeledField("Age", text: $age, keyboard: .numberPad)
                    labeledField("Weight (lbs)", text: $weightLbs, keyboard: .decimalPad)
                }

                HStack(spacing: 12) {
                    labeledField("Height (ft)", text: $heightFeet, keyboard: .numberPad)
                    labeledField("Height (in)", text: $heightInchesPartial, keyboard: .numberPad)
                    labeledField("Training (months)", text: $trainingAgeMonths, keyboard: .numberPad)
                }

                Text("Goals")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                goalSelectionGrid
            }
            .padding(24)
        }
    }

    private var goalSelectionGrid: some View {
        FlowLayout(spacing: 8) {
            ForEach(goalOptions, id: \.self) { goal in
                goalChip(goal)
            }
        }
    }

    private func goalChip(_ goal: String) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button(action: { toggleGoal(goal) }) {
            Text(goal)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : AppTheme.surface)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : AppTheme.surfaceElevated, lineWidth: 1)
                )
        }
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Split Days")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Name your training days however you like. These are suggestions to get started.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                presetSuggestions
                currentSplitDaysList
                addCustomDayField
            }
            .padding(24)
        }
    }

    private var presetSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Presets")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            presetButton("PPL", days: ["Push", "Pull", "Legs"])
            presetButton("Bro Split", days: ["Chest", "Back", "Shoulders", "Arms", "Legs"])
            presetButton("Upper / Lower", days: ["Upper", "Lower"])
            presetButton("Arnold", days: ["Chest & Back", "Shoulders & Arms", "Legs"])
        }
    }

    private func presetButton(_ name: String, days: [String]) -> some View {
        let isActive = splitDays == days
        return Button(action: { splitDays = days }) {
            HStack {
                Text(name).fontWeight(.medium).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(days.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(12)
            .background(isActive ? AppTheme.accent.opacity(0.15) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? AppTheme.accent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var currentSplitDaysList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !splitDays.isEmpty {
                Text("Your Days")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 8)
                ForEach(Array(splitDays.enumerated()), id: \.offset) { index, day in
                    splitDayRow(day, at: index)
                }
            }
        }
    }

    private func splitDayRow(_ day: String, at index: Int) -> some View {
        HStack {
            Text(day).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button(action: { splitDays.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var addCustomDayField: some View {
        HStack {
            TextField("Add custom day (e.g. Heavy Pull)", text: $newDayLabel)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: addCustomDay) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }
            .disabled(newDayLabel.trimmingCharacters(in: .whitespaces).isEmpty)
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
        EquipmentPickerView(selectedEquipment: $selectedEquipment)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") { currentStep -= 1 }
                    .font(.headline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            Spacer()
            if currentStep < 2 {
                Button("Next") { currentStep += 1 }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else {
                Button("Finish") { completeOnboarding() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func completeOnboarding() {
        guard let userId = environment.authService.currentUser()?.userId else { return }

        let profile = UserProfile.create(
            userId: userId,
            displayName: displayName.isEmpty ? nil : displayName,
            age: Int(age),
            heightInches: Double((Int(heightFeet) ?? 0) * 12 + (Int(heightInchesPartial) ?? 0)),
            weightLbs: Double(weightLbs),
            trainingAgeMonths: Int(trainingAgeMonths),
            primaryGoals: Array(selectedGoals),
            splitDays: splitDays,
            avoidExercises: [],
            equipment: selectedEquipment,
            notesToCoach: nil
        )

        environment.profileRepository.saveProfile(profile)
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        environment.hasCompletedOnboarding = true
    }

    // MARK: - Helpers

    private func themedField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .padding(14)
            .background(AppTheme.surfaceElevated)
            .foregroundStyle(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(AppTheme.textSecondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
