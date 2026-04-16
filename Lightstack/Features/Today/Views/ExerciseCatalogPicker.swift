import SwiftUI

/// Searchable, filterable exercise catalog presented as a sheet.
struct ExerciseCatalogPicker: View {

    let onSelect: (String, String) -> Void  // (name, muscleGroup)
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedClassification = "All"
    @State private var showCustomAlert = false
    @State private var customName = ""
    @State private var customMuscleGroup = "Chest"

    private var filteredExercises: [CatalogExercise] {
        ExerciseCatalog.filtered(
            muscleGroup: selectedMuscleGroup,
            classification: selectedClassification,
            search: searchText
        )
    }

    private var groupedExercises: [(String, [CatalogExercise])] {
        let dict = Dictionary(grouping: filteredExercises) { exercise in
            String(exercise.name.prefix(1)).uppercased()
        }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("Search exercises…", text: $searchText)
                        .font(AppTheme.caveat(18))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Filter row
                HStack(spacing: 10) {
                    filterMenu(title: "Muscle Group", selection: $selectedMuscleGroup,
                               options: ["All"] + ExerciseCatalog.muscleGroups)
                    filterMenu(title: "Equipment", selection: $selectedClassification,
                               options: ["All"] + ExerciseCatalog.classifications)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

                // Exercise list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedExercises, id: \.0) { letter, exercises in
                            Section {
                                ForEach(exercises) { exercise in
                                    exerciseRow(exercise)
                                }
                            } header: {
                                Text(letter)
                                    .font(AppTheme.playfair(14, weight: .bold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.background)
                            }
                        }
                    }
                }

                // Add custom exercise button
                Button(action: { showCustomAlert = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Custom Exercise")
                    }
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Exercise Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .alert("Add Custom Exercise", isPresented: $showCustomAlert) {
                TextField("Exercise name", text: $customName)
                Picker("Muscle Group", selection: $customMuscleGroup) {
                    ForEach(ExerciseCatalog.muscleGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                Button("Add") {
                    let name = customName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    onSelect(name, customMuscleGroup)
                    customName = ""
                    dismiss()
                }
                Button("Cancel", role: .cancel) { customName = "" }
            } message: {
                Text("Enter the exercise name and select a muscle group.")
            }
        }
    }

    // MARK: - Subviews

    private func exerciseRow(_ exercise: CatalogExercise) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                onSelect(exercise.name, exercise.muscleGroup)
                dismiss()
            }) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(AppTheme.caveat(18))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(exercise.primaryMuscle)
                            .font(AppTheme.plexMono(11, weight: .regular))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    Text(exercise.classification)
                        .font(AppTheme.plexMono(10, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            InkDivider()
                .padding(.horizontal, 16)
        }
    }

    private func filterMenu(title: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(action: { selection.wrappedValue = option }) {
                    if option == selection.wrappedValue {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.wrappedValue == "All" ? title : selection.wrappedValue)
                    .font(AppTheme.plexMono(12, weight: .medium))
                    .foregroundStyle(selection.wrappedValue == "All" ? AppTheme.textSecondary : AppTheme.accent)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selection.wrappedValue == "All" ? AppTheme.border : AppTheme.accent.opacity(0.4), lineWidth: 1)
            )
        }
    }
}
