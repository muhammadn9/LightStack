import SwiftUI

// MARK: - Badge

/// Small "Recipe" / "Meal" tag next to a name.
struct KitchenBadge: View {
    let text: String
    let icon: String
    let id: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.accent.opacity(0.14), in: Capsule())
            .accessibilityIdentifier(id)
    }
}

// MARK: - Type icon

enum KitchenIcon {
    static let food = "carrot"
    static let meal = "fork.knife"
    static let recipe = "frying.pan"

    static func name(for kind: FoodCollectionKind) -> String { kind == .meal ? meal : recipe }
}

/// Round icon that tells foods, meals and recipes apart.
struct KitchenTypeIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 40, height: 40)
            .background(AppTheme.accent.opacity(0.14), in: Circle())
            .frame(width: 44)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

extension KitchenCollection {
    /// "3 items" for a meal, "makes 2 servings" for a recipe.
    var subtitle: String {
        if kind == .meal {
            let count = lines.count
            return "\(count) \(count == 1 ? "item" : "items")"
        }
        let yield = collection.servingsYield
        return "makes \(ServingUnitConverter.format(yield)) \(yield == 1 ? "serving" : "servings")"
    }
}

/// One saved meal or recipe: type icon, name, subtitle and macros (per serving for a recipe, totals for a meal).
struct CollectionRowView<Accessory: View>: View {
    let item: KitchenCollection
    var showBadge = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            KitchenTypeIcon(systemName: KitchenIcon.name(for: item.kind))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                if showBadge {
                    KitchenBadge(text: item.kind == .meal ? "Meal" : "Recipe", icon: KitchenIcon.name(for: item.kind),
                                 id: item.kind == .meal ? "food.mealBadge" : "food.recipeBadge")
                }
                Text(item.subtitle).font(.subheadline).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                MacroSummaryLine(nutrients: item.perServing, font: .subheadline.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

/// A saved food in the Kitchen list, with the type icon instead of an emoji.
struct KitchenFoodRow<Accessory: View>: View {
    let food: NutritionFood
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            KitchenTypeIcon(systemName: KitchenIcon.food)
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                if food.isAIEstimate { AIEstimateBadge() }
                Text(food.servingLabel).font(.subheadline).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                MacroSummaryLine(nutrients: food.nutrients, font: .subheadline.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Food picker

/// Pick one saved food (for a meal or recipe). `allowed` hides foods that cannot be used.
struct FoodPickerSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let title: String
    var allowed: (NutritionFood) -> Bool = { _ in true }
    let onPick: (NutritionFood) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var foods: [NutritionFood] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        if foods.isEmpty {
                            Text(query.isEmpty ? "No saved foods yet." : "No saved foods match.")
                                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                                .accessibilityIdentifier("picker.empty")
                        } else {
                            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                                if index > 0 { Divider().padding(.leading, 70) }
                                Button {
                                    onPick(food)
                                    dismiss()
                                } label: {
                                    FoodRowView(food: food) { EmptyView() }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("picker.food.\(food.name)")
                            }
                        }
                    }
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                PillSearchField(text: $query, prompt: "Search food", id: "picker.search")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel") } }
            .onAppear(perform: reload)
            .onChange(of: query) { _, _ in reload() }
        }
        .keyboardDoneButton()
    }

    private func reload() {
        foods = viewModel.searchFoods(query).filter(allowed)
    }
}

// MARK: - Log a saved meal

/// Confirm logging a saved meal: its items, an optional multiplier and the slot it goes to.
struct MealLogSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    let meal: KitchenCollection
    let slotName: String
    let slotId: UUID?
    let onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var multiplier = "1"

    private var factor: Double? { NutritionFormat.parse(multiplier).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(meal.lines.enumerated()), id: \.offset) { index, line in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.food.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                                Text("\(NutritionFormat.amount(line.servings * (factor ?? 1))) × \(line.food.servingLabel)")
                                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Text("\(NutritionFormat.whole(line.food.nutrients.kcal * line.servings * (factor ?? 1))) kcal")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("meal.log.item.\(index)")
                    }
                } header: { Text(meal.name) }
                .listRowBackground(AppTheme.surface)

                Section {
                    NutritionField(title: "Multiplier", unit: "×", text: $multiplier, id: "meal.multiplier", placeholder: "1")
                    MacroSummaryLine(nutrients: meal.total.scaled(by: factor ?? 1))
                        .accessibilityIdentifier("meal.log.total")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Button { log() } label: {
                        Text("Log to \(slotName)").font(.headline).foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(factor == nil ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(factor == nil)
                    .accessibilityIdentifier("meal.log")
                }
                .listRowBackground(Color.clear)
            }
            .nutritionFormStyle()
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func log() {
        guard let factor else { return }
        viewModel.logMeal(meal, mealSlotId: slotId, servingsMultiplier: factor)
        onLogged()
        dismiss()
    }
}
