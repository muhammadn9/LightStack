import SwiftUI

/// Log calories and macros without saving a food. Name is optional.
struct QuickAddView: View {
    @ObservedObject var viewModel: NutritionViewModel
    /// The meal to log into (nil = no meal).
    var mealSlotId: UUID?
    var onAdded: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var micros: [MicroKey: String] = [:]
    @State private var showMicros = false

    private var nutrients: NutrientValues? {
        let k = NutritionFormat.parse(kcal)
        let p = NutritionFormat.parse(protein)
        let c = NutritionFormat.parse(carbs)
        let f = NutritionFormat.parse(fat)
        guard k != nil || p != nil || c != nil || f != nil else { return nil }
        let protein = max(0, p ?? 0), carbs = max(0, c ?? 0), fat = max(0, f ?? 0)
        let calories = max(0, k ?? NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat))
        return NutrientValues(kcal: calories, protein: protein, carbs: carbs, fat: fat, micros: Micronutrients(texts: micros))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("nutrition.quickAdd.name")
                    NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "nutrition.quickAdd.kcal")
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "nutrition.quickAdd.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "nutrition.quickAdd.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "nutrition.quickAdd.fat")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    DisclosureGroup("Micronutrients (optional)", isExpanded: $showMicros) {
                        MicroFieldsSection(values: $micros, idPrefix: "nutrition.quickAdd.micro")
                    }
                    .tint(AppTheme.accent)
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let nutrients else { return }
                        viewModel.quickAdd(name: name, nutrients: nutrients, mealSlotId: mealSlotId)
                        onAdded?()
                        dismiss()
                    }
                    .disabled(nutrients == nil)
                    .accessibilityIdentifier("nutrition.quickAdd.save")
                }
            }
        }
    }
}
