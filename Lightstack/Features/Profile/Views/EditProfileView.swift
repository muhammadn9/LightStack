import SwiftUI

/// Modal sheet for editing profile information.
struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let userId: UUID
    let userEmail: String

    @State private var newSplitDay: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        profileSection
                        EditProfileGoalsSection(editGoals: $viewModel.editGoals)
                        EditProfileSplitDaysSection(viewModel: viewModel, newSplitDay: $newSplitDay)
                        EditProfileEquipmentSection(
                            editEquipment: $viewModel.editEquipment,
                            editCustomEquipment: $viewModel.editCustomEquipment
                        )
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
