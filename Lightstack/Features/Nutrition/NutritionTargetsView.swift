import SwiftUI

/// Daily calorie and macro targets. Calories derive from the macros (4/4/9) unless overridden.
struct NutritionTargetsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var overrideKcal = false
    @State private var kcal = ""
    @State private var loaded = false

    private var proteinValue: Double { max(0, NutritionFormat.parse(protein) ?? 0) }
    private var carbsValue: Double { max(0, NutritionFormat.parse(carbs) ?? 0) }
    private var fatValue: Double { max(0, NutritionFormat.parse(fat) ?? 0) }
    private var derived: Double { NutritionMath.derivedKcal(protein: proteinValue, carbs: carbsValue, fat: fatValue) }
    private var typedKcal: Double? { NutritionFormat.parse(kcal).map { max(0, $0) } }
    private var mismatch: Double? {
        guard overrideKcal, let typedKcal else { return nil }
        let diff = typedKcal - derived
        return abs(diff) >= 1 ? diff : nil
    }
    private var canSave: Bool {
        (proteinValue > 0 || carbsValue > 0 || fatValue > 0) || (overrideKcal && (typedKcal ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "nutrition.target.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "nutrition.target.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "nutrition.target.fat")
                } header: {
                    Text("Macros per day")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    HStack {
                        Text("Calories from macros").foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(NutritionFormat.whole(derived)) kcal")
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("nutrition.target.derived")
                    }
                    Toggle("Set calories myself", isOn: $overrideKcal)
                        .tint(AppTheme.accent)
                        .accessibilityIdentifier("nutrition.target.override")
                    if overrideKcal {
                        NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "nutrition.target.kcal")
                        if let mismatch {
                            Label(mismatchText(mismatch), systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("nutrition.target.mismatch")
                        }
                    }
                } header: {
                    Text("Calories")
                } footer: {
                    Text("Calories are worked out as 4 per gram of protein and carbs and 9 per gram of fat unless you set your own.")
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Daily targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveTarget(protein: proteinValue, carbs: carbsValue, fat: fatValue,
                                             kcalOverride: overrideKcal ? typedKcal : nil)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("nutrition.target.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func mismatchText(_ diff: Double) -> String {
        let amount = NutritionFormat.whole(abs(diff))
        return diff > 0 ? "\(amount) kcal more than the macros add up to" : "\(amount) kcal fewer than the macros add up to"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let target = viewModel.currentTarget() else { return }
        protein = NutritionFormat.field(target.protein)
        carbs = NutritionFormat.field(target.carbs)
        fat = NutritionFormat.field(target.fat)
        overrideKcal = target.kcalOverridden
        kcal = NutritionFormat.field(target.kcal)
    }
}
