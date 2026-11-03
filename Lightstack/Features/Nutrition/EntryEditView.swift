import SwiftUI

// MARK: - Edit a logged entry

struct EntryEditView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var servings = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var loaded = false
    @State private var slotId: UUID?

    private var servingsValue: Double? { NutritionFormat.parse(servings).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { servingsValue != nil && NutritionFormat.parse(kcal) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("nutrition.entryEdit.name")
                    NutritionField(title: "Servings", unit: "", text: $servings, id: "nutrition.entryEdit.servings", placeholder: "1")
                    Text("One serving is \(entry.servingLabel).")
                        .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "nutrition.entryEdit.kcal")
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "nutrition.entryEdit.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "nutrition.entryEdit.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "nutrition.entryEdit.fat")
                } header: {
                    Text("Per serving")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Picker("Meal", selection: $slotId) {
                        Text("No meal").tag(UUID?.none)
                        ForEach(viewModel.slots) { slot in Text(slot.name).tag(UUID?.some(slot.id)) }
                    }
                    .accessibilityIdentifier("nutrition.entryEdit.meal")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Button(role: .destructive) {
                        viewModel.delete(entry)
                        dismiss()
                    } label: {
                        Label("Delete entry", systemImage: "trash").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("nutrition.entryEdit.delete")
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("nutrition.entryEdit.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = entry.name
        slotId = entry.mealSlotId
        servings = NutritionFormat.field(entry.servings)
        kcal = NutritionFormat.field(entry.perServing.kcal)
        protein = NutritionFormat.field(entry.perServing.protein)
        carbs = NutritionFormat.field(entry.perServing.carbs)
        fat = NutritionFormat.field(entry.perServing.fat)
    }

    private func save() {
        guard let servingsValue else { return }
        var updated = entry
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? entry.name : trimmed
        updated.servings = servingsValue
        updated.perServing.kcal = max(0, NutritionFormat.parse(kcal) ?? entry.perServing.kcal)
        updated.perServing.protein = max(0, NutritionFormat.parse(protein) ?? 0)
        updated.perServing.carbs = max(0, NutritionFormat.parse(carbs) ?? 0)
        updated.perServing.fat = max(0, NutritionFormat.parse(fat) ?? 0)
        updated.mealSlotId = slotId
        viewModel.update(updated)
        dismiss()
    }
}
