import SwiftUI

/// Three-step onboarding flow:
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
    @State private var heightInches = ""
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
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
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

                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    labeledField("Age", text: $age, keyboard: .numberPad)
                    labeledField("Weight (lbs)", text: $weightLbs, keyboard: .decimalPad)
                }

                HStack(spacing: 12) {
                    labeledField("Height (in)", text: $heightInches, keyboard: .decimalPad)
                    labeledField("Training (months)", text: $trainingAgeMonths, keyboard: .numberPad)
                }

                Text("Goals")
                    .font(.headline)
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
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
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
                Text("Name your training days however you like. These are suggestions to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
            presetButton("PPL", days: ["Push", "Pull", "Legs"])
            presetButton("Bro Split", days: ["Chest", "Back", "Shoulders", "Arms", "Legs"])
            presetButton("Upper / Lower", days: ["Upper", "Lower"])
            presetButton("Arnold", days: ["Chest & Back", "Shoulders & Arms", "Legs"])
        }
    }

    private func presetButton(_ name: String, days: [String]) -> some View {
        Button(action: { splitDays = days }) {
            HStack {
                Text(name).fontWeight(.medium)
                Spacer()
                Text(days.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var currentSplitDaysList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !splitDays.isEmpty {
                Text("Your Days")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(Array(splitDays.enumerated()), id: \.offset) { index, day in
                    splitDayRow(day, at: index)
                }
            }
        }
    }

    private func splitDayRow(_ day: String, at index: Int) -> some View {
        HStack {
            Text(day)
            Spacer()
            Button(action: { splitDays.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var addCustomDayField: some View {
        HStack {
            TextField("Add custom day (e.g. Heavy Pull)", text: $newDayLabel)
                .textFieldStyle(.roundedBorder)
            Button(action: addCustomDay) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
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
                    .buttonStyle(.bordered)
            }
            Spacer()
            if currentStep < 2 {
                Button("Next") { currentStep += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Finish") { completeOnboarding() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func completeOnboarding() {
        // TODO: Save profile to Core Data + Supabase via ProfileRepository
        environment.hasCompletedOnboarding = true
    }

    // MARK: - Helpers

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - FlowLayout

/// Simple flow layout for wrapping chips/tags horizontally.
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
