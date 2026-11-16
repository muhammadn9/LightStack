import SwiftUI

/// One exercise chosen in the picker.
struct PickedExercise: Equatable {
    let name: String
    let muscleGroup: String
}

/// Searchable, filterable exercise catalog presented as a sheet.
/// Lists the athlete's most recent lifts first ("Recent"), then every exercise A to Z. With `onAddMany` it is a
/// multi-select: tick several rows and add them all, in the order ticked.
struct ExerciseCatalogPicker: View {

    /// Exercises the user has done before, most recent first: the first few are the "Recent" group, and any
    /// that are not in the catalog join the A to Z list.
    var loadYourExercises: (() -> [HistoryExercise])? = nil
    @State private var yourExercises: [HistoryExercise] = []
    /// Past exercise names used only for "Did you mean" suggestions on custom names
    /// (does not add the "Recent" group). Defaults to `loadYourExercises`.
    var loadKnownExercises: (() -> [HistoryExercise])? = nil
    @State private var knownExercises: [HistoryExercise] = []
    /// The lifts shown as "Recent" (most recent first). Defaults to the first few of `loadYourExercises`.
    var loadRecent: (() -> [HistoryExercise])? = nil
    @State private var recentExercises: [HistoryExercise] = []
    @State private var nameSuggestion: NameSuggestion?
    /// Single-select: called with the chosen exercise, then the picker closes.
    var onSelect: ((String, String) -> Void)?
    /// Multi-select: called once with everything ticked, in tick order, then the picker closes.
    var onAddMany: (([PickedExercise]) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedClassification = "All"
    @State private var showCustomForm = false
    @State private var customName = ""
    @State private var customMuscleGroup = "Chest"
    @State private var picks: [PickedExercise] = []

    /// How many past lifts the "Recent" group shows.
    static let recentLimit = 5

    init(loadYourExercises: (() -> [HistoryExercise])? = nil,
         loadKnownExercises: (() -> [HistoryExercise])? = nil,
         loadRecent: (() -> [HistoryExercise])? = nil,
         onSelect: @escaping (String, String) -> Void) {
        self.loadRecent = loadRecent
        self.loadYourExercises = loadYourExercises
        self.loadKnownExercises = loadKnownExercises
        self.onSelect = onSelect
    }

    /// Multi-select picker: tick several exercises and add them together.
    init(loadYourExercises: (() -> [HistoryExercise])? = nil,
         loadKnownExercises: (() -> [HistoryExercise])? = nil,
         loadRecent: (() -> [HistoryExercise])? = nil,
         onAddMany: @escaping ([PickedExercise]) -> Void) {
        self.loadRecent = loadRecent
        self.loadYourExercises = loadYourExercises
        self.loadKnownExercises = loadKnownExercises
        self.onAddMany = onAddMany
    }

    private var isMultiSelect: Bool { onAddMany != nil }

    /// A custom name that closely matches something already logged.
    struct NameSuggestion: Equatable {
        let typed: String
        let typedMuscleGroup: String
        let existing: HistoryExercise
    }

    /// One row of the picker.
    struct Row: Identifiable, Equatable {
        let name: String
        let muscleGroup: String
        var id: String { name.lowercased() }
    }

    /// The "Recent" group: the last few distinct lifts, narrowed by search and the muscle filter
    /// (history carries no equipment type, so an equipment filter hides it).
    static func recentRows(history: [HistoryExercise], search: String, muscleGroup: String,
                           classification: String, limit: Int = recentLimit) -> [Row] {
        guard classification == "All" else { return [] }
        return HistoryExercise.filtered(Array(history.prefix(limit)), search: search)
            .filter { muscleGroup == "All" || $0.muscleGroup.caseInsensitiveCompare(muscleGroup) == .orderedSame }
            .map { Row(name: $0.name, muscleGroup: $0.muscleGroup) }
    }

    /// Everything A to Z: the catalog (filtered) plus lifts from the athlete's history that the catalog lacks.
    static func allRows(history: [HistoryExercise], search: String, muscleGroup: String,
                        classification: String, catalog: [CatalogExercise]? = nil) -> [Row] {
        let catalogRows = (catalog ?? ExerciseCatalog.filtered(
            muscleGroup: muscleGroup, classification: classification, search: search))
            .map { Row(name: $0.name, muscleGroup: $0.muscleGroup) }
        var seen = Set((catalog ?? ExerciseCatalog.exercises).map { PersonalRecordsListView.exerciseKey($0.name) })
        var rows = catalogRows
        if classification == "All" {
            for item in HistoryExercise.filtered(history, search: search)
            where muscleGroup == "All" || item.muscleGroup.caseInsensitiveCompare(muscleGroup) == .orderedSame {
                guard seen.insert(PersonalRecordsListView.exerciseKey(item.name)).inserted else { continue }
                rows.append(Row(name: item.name, muscleGroup: item.muscleGroup))
            }
        }
        return ExerciseSort.azSorted(rows, by: \.name)
    }

    private var recentRows: [Row] {
        Self.recentRows(history: recentExercises, search: searchText, muscleGroup: selectedMuscleGroup,
                        classification: selectedClassification)
    }

    private var allRows: [Row] {
        Self.allRows(history: yourExercises, search: searchText, muscleGroup: selectedMuscleGroup,
                     classification: selectedClassification)
    }

    private func isPicked(_ row: Row) -> Bool {
        picks.contains { $0.name.lowercased() == row.id }
    }

    private func toggle(_ row: Row) {
        if let index = picks.firstIndex(where: { $0.name.lowercased() == row.id }) {
            picks.remove(at: index)
        } else {
            picks.append(PickedExercise(name: row.name, muscleGroup: row.muscleGroup))
        }
    }

    private func choose(_ row: Row) {
        if isMultiSelect {
            toggle(row)
        } else {
            onSelect?(row.name, row.muscleGroup)
            dismiss()
        }
    }

    /// Adds the ticked exercises plus any extra, in order, and closes.
    private func commit(extra: PickedExercise? = nil) {
        if isMultiSelect {
            onAddMany?(picks + (extra.map { [$0] } ?? []))
        } else if let extra {
            onSelect?(extra.name, extra.muscleGroup)
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("Search exercises", text: $searchText)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("exerciseSearchField")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Filter row
                HStack(spacing: 10) {
                    filterMenu(title: "Muscle Group", selection: $selectedMuscleGroup,
                               options: ["All"] + ExerciseCatalog.muscleGroups)
                    filterMenu(title: "Equipment", selection: $selectedClassification,
                               options: ["All"] + ExerciseCatalog.classifications)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

                // Exercise list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !recentRows.isEmpty {
                            sectionTitle("Recent", id: "recentExercisesHeader")
                            card {
                                ForEach(recentRows) { row in
                                    exerciseRow(row, idPrefix: "pickerRecent", showsSubtitleBelow: true)
                                }
                            }
                        }
                        sectionTitle("All exercises, A to Z", id: "allExercisesHeader")
                        card {
                            ForEach(allRows) { row in
                                exerciseRow(row, idPrefix: "pickerRow", showsSubtitleBelow: false)
                            }
                        }
                        if allRows.isEmpty {
                            Text("No exercises match. Add a custom one below.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                if let suggestion = nameSuggestion {
                    ExerciseNameSuggestionRow(
                        existingName: suggestion.existing.name,
                        onUse: {
                            let extra = PickedExercise(name: suggestion.existing.name, muscleGroup: suggestion.existing.muscleGroup)
                            nameSuggestion = nil
                            commit(extra: extra)
                        },
                        onKeep: {
                            let extra = PickedExercise(name: suggestion.typed, muscleGroup: suggestion.typedMuscleGroup)
                            nameSuggestion = nil
                            commit(extra: extra)
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

                bottomBar
            }
            .background(AppTheme.background.ignoresSafeArea())
            .onAppear {
                yourExercises = loadYourExercises?() ?? []
                recentExercises = loadRecent?() ?? yourExercises
                knownExercises = loadKnownExercises?() ?? yourExercises
            }
            .navigationTitle(isMultiSelect ? "Add exercises" : "Exercise Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("pickerCancelButton")
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button(action: { showCustomForm = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Custom Exercise")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("addCustomExerciseButton")

            if isMultiSelect {
                Button(action: { commit() }) {
                    Text(picks.isEmpty ? "Select exercises" : "Add \(picks.count) \(picks.count == 1 ? "exercise" : "exercises")")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppTheme.accent, in: Capsule())
                        .opacity(picks.isEmpty ? 0.45 : 1)
                }
                .disabled(picks.isEmpty)
                .accessibilityIdentifier("pickerAddButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppTheme.background)
    }

    private func sectionTitle(_ title: String, id: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        customName = ""
        commit(extra: PickedExercise(name: name, muscleGroup: customMuscleGroup))
    }

    // MARK: - Subviews

    private func exerciseRow(_ row: Row, idPrefix: String, showsSubtitleBelow: Bool) -> some View {
        let picked = isPicked(row)
        return VStack(spacing: 0) {
            Button(action: { choose(row) }) {
                HStack(spacing: 12) {
                    if isMultiSelect {
                        ZStack {
                            Circle()
                                .strokeBorder(picked ? AppTheme.accent : AppTheme.textSecondary, lineWidth: 2)
                                .background(Circle().fill(picked ? AppTheme.accent : Color.clear))
                            if picked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(AppTheme.onAccent)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    if showsSubtitleBelow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(row.muscleGroup)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    } else {
                        Text(row.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer(minLength: 8)
                        Text(row.muscleGroup)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue(isMultiSelect ? (picked ? "selected" : "not selected") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("\(idPrefix).\(row.name)")

            Divider()
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
