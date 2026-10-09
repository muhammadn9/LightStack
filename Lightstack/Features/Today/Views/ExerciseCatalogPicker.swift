import SwiftUI

/// Searchable, filterable exercise catalog presented as a sheet.
struct ExerciseCatalogPicker: View {

    /// Exercises the user has done before, shown first as "Your exercises".
    var loadYourExercises: (() -> [HistoryExercise])? = nil
    @State private var yourExercises: [HistoryExercise] = []
    /// Past exercise names used only for "Did you mean" suggestions on custom names
    /// (does not add the "Your exercises" section). Defaults to `loadYourExercises`.
    var loadKnownExercises: (() -> [HistoryExercise])? = nil
    @State private var knownExercises: [HistoryExercise] = []
    @State private var nameSuggestion: NameSuggestion?
    let onSelect: (String, String) -> Void  // (name, muscleGroup)
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedClassification = "All"
    @State private var showCustomForm = false
    @State private var customName = ""
    @State private var customMuscleGroup = "Chest"

    /// A custom name that closely matches something already logged.
    struct NameSuggestion: Equatable {
        let typed: String
        let typedMuscleGroup: String
        let existing: HistoryExercise
    }

    private var filteredExercises: [CatalogExercise] {
        ExerciseCatalog.filtered(
            muscleGroup: selectedMuscleGroup,
            classification: selectedClassification,
            search: searchText
        )
    }

    private var filteredYourExercises: [HistoryExercise] {
        HistoryExercise.filtered(yourExercises, search: searchText)
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
                        .accessibilityIdentifier("exerciseSearchField")
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
                        if !filteredYourExercises.isEmpty {
                            Section {
                                ForEach(filteredYourExercises) { item in
                                    yourExerciseRow(item)
                                }
                            } header: {
                                Text("Your exercises")
                                    .font(AppTheme.playfair(14, weight: .bold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.background)
                                    .accessibilityIdentifier("yourExercisesHeader")
                            }
                        }
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

                if let suggestion = nameSuggestion {
                    ExerciseNameSuggestionRow(
                        existingName: suggestion.existing.name,
                        onUse: {
                            onSelect(suggestion.existing.name, suggestion.existing.muscleGroup)
                            nameSuggestion = nil
                            dismiss()
                        },
                        onKeep: {
                            onSelect(suggestion.typed, suggestion.typedMuscleGroup)
                            nameSuggestion = nil
                            dismiss()
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if showCustomForm && nameSuggestion == nil {
                    customForm
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // Add custom exercise button
                Button(action: { showCustomForm = true }) {
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
                .accessibilityIdentifier("addCustomExerciseButton")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .onAppear {
                yourExercises = loadYourExercises?() ?? []
                knownExercises = loadKnownExercises?() ?? yourExercises
            }
            .navigationTitle("Exercise Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    // MARK: - Custom exercise

    private var customForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Exercise name", text: $customName)
                .font(AppTheme.caveat(18))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(10)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("customExerciseNameField")
            HStack {
                Picker("Muscle Group", selection: $customMuscleGroup) {
                    ForEach(ExerciseCatalog.muscleGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .tint(AppTheme.accent)
                Spacer()
                Button("Add", action: submitCustomName)
                    .font(AppTheme.playfairItalic(15, weight: .bold))
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("customExerciseAddButton")
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
    }

    private func submitCustomName() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let known = knownExercises.map(\.name)
        if let match = ExerciseNameResolver.suggestions(for: name, among: known).first,
           let existing = knownExercises.first(where: { $0.name == match }) {
            nameSuggestion = NameSuggestion(typed: name, typedMuscleGroup: customMuscleGroup, existing: existing)
            customName = ""
            return
        }
        onSelect(name, customMuscleGroup)
        customName = ""
        dismiss()
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

    private func yourExerciseRow(_ item: HistoryExercise) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                onSelect(item.name, item.muscleGroup)
                dismiss()
            }) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(AppTheme.caveat(18))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(item.muscleGroup)
                            .font(AppTheme.plexMono(11, weight: .regular))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("yourExercise.\(item.name)")

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
