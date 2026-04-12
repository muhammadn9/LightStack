import SwiftUI

/// Modal sheet for editing profile information.
struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let userId: UUID
    let userEmail: String

    @State private var newCustomGoal: String = ""
    @State private var newSplitDay: String = ""

    private let goalOptions = [
        "Build Muscle", "Get Stronger", "Lose Fat",
        "Improve Endurance", "Stay Healthy"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        profileSection
                        goalsSection
                        splitDaysSection
                        equipmentSection
                        notesSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveProfile(userId: userId)
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                    .disabled(viewModel.isSaving)
                }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile Info")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            themedField("Display Name", text: $viewModel.editDisplayName)

            VStack(alignment: .leading, spacing: 4) {
                Text("Email").font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary)
                Text(userEmail)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceElevated)
                    .foregroundStyle(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }

            HStack(spacing: 12) {
                labeledField("Age", text: $viewModel.editAge, keyboard: .numberPad)
                labeledField("Weight (lbs)", text: $viewModel.editWeightLbs, keyboard: .decimalPad)
            }

            HStack(spacing: 12) {
                labeledField("Height (ft)", text: $viewModel.editHeightFeet, keyboard: .numberPad)
                labeledField("Height (in)", text: $viewModel.editHeightInches, keyboard: .numberPad)
                labeledField("Training (months)", text: $viewModel.editTrainingAgeMonths, keyboard: .numberPad)
            }
        }
        .cardStyle()
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goals")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            FlowLayout(spacing: 8) {
                ForEach(goalOptions, id: \.self) { goal in
                    goalChip(goal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Custom goals added by the user
            let customGoals = viewModel.editGoals.filter { !goalOptions.contains($0) }.sorted()
            if !customGoals.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(customGoals, id: \.self) { goal in
                        customGoalChip(goal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                TextField("Add custom goal", text: $newCustomGoal)
                    .padding(12)
                    .background(AppTheme.surfaceElevated)
                    .foregroundStyle(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .onSubmit { addCustomGoal() }
                Button(action: addCustomGoal) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            newCustomGoal.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AppTheme.textSecondary : AppTheme.accent
                        )
                }
                .disabled(newCustomGoal.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .cardStyle()
    }

    private func addCustomGoal() {
        let trimmed = newCustomGoal.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.editGoals.insert(trimmed)
        newCustomGoal = ""
    }

    private func customGoalChip(_ goal: String) -> some View {
        HStack(spacing: 4) {
            Text(goal)
                .font(AppTheme.caveat(14))
            Button(action: { viewModel.editGoals.remove(goal) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTheme.caveat(11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.accent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func goalChip(_ goal: String) -> some View {
        let isSelected = viewModel.editGoals.contains(goal)
        return Button(action: { toggleGoal(goal) }) {
            Text(goal)
                .font(AppTheme.caveat(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : AppTheme.surface)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(isSelected ? Color.clear : AppTheme.surfaceElevated, lineWidth: 1)
                )
        }
    }

    private func toggleGoal(_ goal: String) {
        if viewModel.editGoals.contains(goal) {
            viewModel.editGoals.remove(goal)
        } else {
            viewModel.editGoals.insert(goal)
        }
    }

    // MARK: - Split Days Section

    private var splitDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split Days")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if !viewModel.editSplitDays.isEmpty {
                ForEach(Array(viewModel.editSplitDays.enumerated()), id: \.offset) { index, day in
                    splitDayRow(day, at: index)
                }
            }

            HStack {
                TextField("Add custom day", text: $newSplitDay)
                    .padding(12)
                    .background(AppTheme.surfaceElevated)
                    .foregroundStyle(AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .onSubmit {
                        let trimmed = newSplitDay.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            viewModel.addSplitDay(trimmed)
                            newSplitDay = ""
                        }
                    }
                Button(action: {
                    let trimmed = newSplitDay.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        viewModel.addSplitDay(trimmed)
                        newSplitDay = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(newSplitDay.trimmingCharacters(in: .whitespaces).isEmpty ? AppTheme.textSecondary : AppTheme.accent)
                }
                .disabled(newSplitDay.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .cardStyle()
    }

    private func splitDayRow(_ day: String, at index: Int) -> some View {
        HStack {
            Text(day).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button(action: { viewModel.removeSplitDay(day) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Equipment Section

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(equipmentOptions, id: \.self) { item in
                    equipmentToggle(item)
                }
            }

            InkDivider()
                .padding(.vertical, 8)

            Text("Other Equipment")
                .font(AppTheme.caveat(14))
                .foregroundStyle(AppTheme.textPrimary)

            Text("List any other equipment you have access to")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("Type custom equipment here...", text: $viewModel.editCustomEquipment, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
        }
        .cardStyle()
    }

    private let equipmentOptions = [
        "Dumbbells", "Barbell", "Cables", "Machines",
        "Pull-Up Bar", "Dip Station", "Leg Press",
        "Smith Machine", "Resistance Bands", "Kettlebells"
    ]

    private func equipmentToggle(_ item: String) -> some View {
        let isSelected = viewModel.editEquipment[item] ?? false
        return Button(action: { toggleEquipment(item) }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                Text(item)
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleEquipment(_ item: String) {
        let current = viewModel.editEquipment[item] ?? false
        viewModel.editEquipment[item] = !current
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes to Coach")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g., recovering from shoulder injury", text: $viewModel.editNotesToCoach, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func themedField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .padding(14)
            .background(AppTheme.surfaceElevated)
            .foregroundStyle(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }
}
