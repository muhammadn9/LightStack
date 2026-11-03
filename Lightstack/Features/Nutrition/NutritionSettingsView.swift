import SwiftUI

/// Settings for the nutrition side: daily meals, tracked nutrients, water unit.
struct NutritionSettingsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { MealsSettingsView(viewModel: viewModel) } label: {
                        Label("Daily Meals", systemImage: "fork.knife")
                    }
                    .accessibilityIdentifier("nutritionSettings.meals")
                    NavigationLink { NutrientsSettingsView(viewModel: viewModel) } label: {
                        Label("Nutrients", systemImage: "chart.bar.doc.horizontal")
                    }
                    .accessibilityIdentifier("nutritionSettings.nutrients")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Picker("Water unit", selection: Binding(get: { viewModel.waterUnit }, set: { viewModel.setWaterUnit($0) })) {
                        Text("fl oz").tag(WaterUnit.flOz)
                        Text("ml").tag(WaterUnit.ml)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("nutritionSettings.waterUnit")
                } header: {
                    Text("Water unit")
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Journal settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("nutritionSettings.done")
                }
            }
        }
        .onDisappear { viewModel.reload() }
    }
}

// MARK: - Daily meals

struct MealsSettingsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var active: [MealSlot] = []
    @State private var archived: [MealSlot] = []
    @State private var renaming: MealSlot?
    @State private var renameText = ""
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(active) { slot in
                    Button {
                        renameText = slot.name
                        renaming = slot
                    } label: {
                        HStack {
                            Text(slot.name).foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("settings.meal.\(slot.name)")
                }
                .onMove { from, to in
                    active.move(fromOffsets: from, toOffset: to)
                    viewModel.reorderMeals(ids: active.map(\.id))
                    refresh()
                }
                .onDelete { offsets in
                    offsets.map { active[$0] }.forEach { viewModel.archiveMeal(id: $0.id) }
                    refresh()
                }
                Button {
                    newName = ""
                    adding = true
                } label: {
                    Label("Add meal", systemImage: "plus.circle.fill").foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.meals.add")
            } header: {
                Text("Meals")
            } footer: {
                Text("Drag to reorder. Removing a meal hides it but keeps what you logged in it.")
            }
            .listRowBackground(AppTheme.surface)

            if !archived.isEmpty {
                Section {
                    ForEach(archived) { slot in
                        HStack {
                            Text(slot.name).foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                            Button("Restore") {
                                viewModel.unarchiveMeal(id: slot.id)
                                refresh()
                            }
                            .accessibilityIdentifier("settings.meal.restore.\(slot.name)")
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text("Removed meals")
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .environment(\.editMode, .constant(.active))
        .nutritionFormStyle()
        .navigationTitle("Daily Meals")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename meal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Meal name", text: $renameText)
            Button("Save") {
                if let slot = renaming { viewModel.renameMeal(id: slot.id, name: renameText) }
                renaming = nil
                refresh()
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New meal", isPresented: $adding) {
            TextField("Meal name", text: $newName)
            Button("Add") {
                viewModel.addMeal(name: newName)
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let all = viewModel.allSlots(includeArchived: true)
        active = all.filter { !$0.isArchived }
        archived = all.filter(\.isArchived)
    }
}

// MARK: - Nutrients

struct NutrientsSettingsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var editing: NutrientTracker?
    @State private var targetText = ""

    var body: some View {
        List {
            Section {
                ForEach(viewModel.trackers) { tracker in
                    Button {
                        editing = tracker
                        targetText = NutritionFormat.field(displayTarget(tracker))
                    } label: {
                        HStack {
                            Text(tracker.nutrient.displayName).foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Text(targetLabel(tracker)).foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("settings.nutrient.\(tracker.nutrient.storageKey)")
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    viewModel.moveTracker(from: source, to: to > source ? to - 1 : to)
                }
                .onDelete { offsets in
                    offsets.map { viewModel.trackers[$0].nutrient }.forEach { viewModel.removeTracker($0) }
                }
                Menu {
                    ForEach(viewModel.availableTrackers) { nutrient in
                        Button(nutrient.displayName) { viewModel.addTracker(nutrient) }
                    }
                } label: {
                    Label("Add nutrient", systemImage: "plus.circle.fill").foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                }
                .disabled(viewModel.availableTrackers.isEmpty)
                .accessibilityIdentifier("settings.nutrients.add")
            } header: {
                Text("Shown on the Journal")
            } footer: {
                Text("Tap a nutrient to set a daily target. Drag to reorder.")
            }
            .listRowBackground(AppTheme.surface)
        }
        .environment(\.editMode, .constant(.active))
        .nutritionFormStyle()
        .navigationTitle("Nutrients")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Daily target", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Target", text: $targetText).keyboardType(.decimalPad)
            Button("Save") {
                if let tracker = editing {
                    let value = NutritionFormat.parse(targetText)
                    let stored = tracker.nutrient == .water ? value.map { viewModel.waterUnit.toMl($0) } : value
                    viewModel.setTrackerTarget(stored, for: tracker.nutrient)
                }
                editing = nil
            }
            Button("Clear") {
                if let tracker = editing { viewModel.setTrackerTarget(nil, for: tracker.nutrient) }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            if let tracker = editing {
                Text("\(tracker.nutrient.displayName) in \(tracker.nutrient == .water ? viewModel.waterUnit.label : tracker.nutrient.unit)")
            }
        }
    }

    private func displayTarget(_ tracker: NutrientTracker) -> Double? {
        guard let target = tracker.dailyTarget else { return nil }
        return tracker.nutrient == .water ? viewModel.waterUnit.fromMl(target) : target
    }

    private func targetLabel(_ tracker: NutrientTracker) -> String {
        guard let target = tracker.dailyTarget else { return "No target" }
        if tracker.nutrient == .water { return viewModel.waterUnit.format(ml: target) }
        return "\(NutritionFormat.amount(target)) \(tracker.nutrient.unit)"
    }
}
