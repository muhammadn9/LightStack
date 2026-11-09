import SwiftUI

/// One editable row of a meal or recipe: a saved food and its servings as typed text.
struct EditorLine: Identifiable {
    let id = UUID()
    var food: NutritionFood
    var text: String

    init(food: NutritionFood, servings: Double = 1) {
        self.food = food
        text = ServingUnitConverter.format(servings)
    }

    var servings: Double? { NutritionFormat.parse(text).flatMap { $0 > 0 ? $0 : nil } }
}

/// The servings row shared by the meal and recipe editors: name, macros, and a − / field / + / remove strip.
struct EditorLineRow: View {
    @Binding var line: EditorLine
    let idPrefix: String
    let index: Int
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.food.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
            HStack(spacing: 0) {
                MacroSummaryLine(nutrients: line.food.nutrients.scaled(by: line.servings ?? 0), font: .caption.weight(.semibold))
                Spacer(minLength: 8)
            }
            HStack(spacing: 0) {
                Button { step(-0.5) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Fewer servings of \(line.food.name)")
                    .accessibilityIdentifier("\(idPrefix).item.\(index).dec")
                TextField("1", text: $line.text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 56, height: 44)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityLabel("Servings of \(line.food.name)")
                    .accessibilityIdentifier("\(idPrefix).item.\(index).servings")
                Button { step(0.5) } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("More servings of \(line.food.name)")
                    .accessibilityIdentifier("\(idPrefix).item.\(index).inc")
                Text("× \(line.food.servingLabel)")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                    .padding(.leading, 6)
                Spacer(minLength: 4)
                Button(role: .destructive, action: onRemove) { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel("Remove \(line.food.name)")
                    .accessibilityIdentifier("\(idPrefix).item.\(index).remove")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 4)
    }

    private func step(_ delta: Double) {
        let current = line.servings ?? 1
        line.text = ServingUnitConverter.format(max(0.5, current + delta))
    }
}

// MARK: - Meal editor

/// Create or edit a saved meal: a name and a list of foods with servings.
struct MealEditorView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var meal: KitchenCollection?
    var initialItems: [PlateItem] = []
    var onSaved: (KitchenCollection) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lines: [EditorLine] = []
    @State private var loaded = false
    @State private var picking = false
    @State private var confirmDelete = false

    private var items: [PlateItem] { lines.compactMap { line in line.servings.map { PlateItem(food: line.food, servings: $0) } } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lines.isEmpty && items.count == lines.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $name).frame(minHeight: 44).accessibilityIdentifier("meal.name")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        EditorLineRow(line: binding(for: line.id), idPrefix: "meal", index: index) {
                            lines.removeAll { $0.id == line.id }
                        }
                    }
                    Button { picking = true } label: {
                        Label("Add food", systemImage: "plus.circle.fill").foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("meal.addFood")
                } header: { Text("Foods") }
                .listRowBackground(AppTheme.surface)

                if meal != nil {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete meal", systemImage: "trash").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("meal.delete")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .nutritionFormStyle()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SummaryBar(title: "Total") {
                    MacroSummaryLine(nutrients: RecipeMath.total(of: items)).accessibilityIdentifier("meal.total")
                }
            }
            .navigationTitle(meal == nil ? "New meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("meal.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("meal.save")
                }
            }
            .sheet(isPresented: $picking) {
                FoodPickerSheet(viewModel: viewModel, title: "Add food") { lines.append(EditorLine(food: $0)) }
            }
            .alert("Delete this meal?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let meal { viewModel.deleteMeal(meal) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Entries you already logged stay in your journal.") }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let meal {
                    name = meal.name
                    lines = meal.lines.map { EditorLine(food: $0.food, servings: $0.servings) }
                } else {
                    lines = initialItems.map { EditorLine(food: $0.food, servings: $0.servings) }
                }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<EditorLine> {
        Binding(
            get: { lines.first { $0.id == id } ?? EditorLine(food: placeholderFood) },
            set: { updated in if let index = lines.firstIndex(where: { $0.id == id }) { lines[index] = updated } }
        )
    }

    private var placeholderFood: NutritionFood {
        NutritionFood.make(userId: viewModel.userId ?? UUID(), name: "", nutrients: NutrientValues(kcal: 0, protein: 0, carbs: 0, fat: 0))
    }

    private func save() {
        guard canSave, let saved = viewModel.saveMeal(id: meal?.id, name: name, items: items) else { return }
        onSaved(saved)
        dismiss()
    }
}

// MARK: - Recipe editor

/// Create or edit a recipe: ingredients, how many servings it makes, an optional cooked weight and a live per-serving preview.
struct RecipeEditorView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var recipe: KitchenCollection?
    var onSaved: (KitchenCollection) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lines: [EditorLine] = []
    @State private var yieldText = "1"
    @State private var cookedWeight = ""
    @State private var loaded = false
    @State private var picking = false
    @State private var confirmDelete = false

    private var items: [PlateItem] { lines.compactMap { line in line.servings.map { PlateItem(food: line.food, servings: $0) } } }
    private var servingsYield: Double? { NutritionFormat.parse(yieldText).flatMap { $0 > 0 ? $0 : nil } }
    private var cookedGrams: Double? { NutritionFormat.parse(cookedWeight).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lines.isEmpty
            && items.count == lines.count && servingsYield != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $name).frame(minHeight: 44).accessibilityIdentifier("recipe.name")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    HStack(spacing: 0) {
                        Text("Makes").foregroundStyle(AppTheme.textPrimary)
                        Spacer(minLength: 8)
                        Button { stepYield(-0.5) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                            .disabled((servingsYield ?? 1) <= 0.5)
                            .accessibilityLabel("Fewer servings")
                            .accessibilityIdentifier("recipe.yield.dec")
                        TextField("1", text: $yieldText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 56, height: 44)
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityLabel("Servings the recipe makes")
                            .accessibilityIdentifier("recipe.yield")
                        Button { stepYield(0.5) } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }
                            .accessibilityLabel("More servings")
                            .accessibilityIdentifier("recipe.yield.inc")
                        Text("servings").foregroundStyle(AppTheme.textSecondary).padding(.leading, 6)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.accent)
                    NutritionField(title: "Cooked weight (optional)", unit: "g", text: $cookedWeight, id: "recipe.cookedWeight", placeholder: "—")
                } header: { Text("Yield") }
                .listRowBackground(AppTheme.surface)

                Section {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        EditorLineRow(line: binding(for: line.id), idPrefix: "recipe", index: index) {
                            lines.removeAll { $0.id == line.id }
                        }
                    }
                    Button { picking = true } label: {
                        Label("Add ingredient", systemImage: "plus.circle.fill").foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("recipe.addIngredient")
                } header: { Text("Ingredients") }
                .listRowBackground(AppTheme.surface)

                if recipe != nil {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete recipe", systemImage: "trash").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("recipe.delete")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .nutritionFormStyle()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let preview = NutritionViewModel.recipePreview(ingredients: items, servingsYield: servingsYield ?? 1,
                                                               cookedWeightGrams: cookedGrams)
                SummaryBar(title: "Per serving") {
                    VStack(alignment: .trailing, spacing: 2) {
                        MacroSummaryLine(nutrients: preview.perServing).accessibilityIdentifier("recipe.perServing")
                        if let grams = preview.servingGrams {
                            Text("About \(NutritionFormat.whole(grams)) g per serving")
                                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("recipe.servingWeight")
                        }
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("recipe.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("recipe.save")
                }
            }
            .sheet(isPresented: $picking) {
                FoodPickerSheet(viewModel: viewModel, title: "Add ingredient",
                                allowed: { viewModel.canUseAsIngredient($0, in: recipe) },
                                onPick: { lines.append(EditorLine(food: $0)) })
            }
            .alert("Delete this recipe?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let recipe { viewModel.deleteRecipe(recipe) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Entries you already logged stay in your journal.") }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let recipe {
                    name = recipe.name
                    lines = recipe.lines.map { EditorLine(food: $0.food, servings: $0.servings) }
                    yieldText = ServingUnitConverter.format(recipe.collection.servingsYield)
                    cookedWeight = recipe.collection.cookedWeightGrams.map { NutritionFormat.field($0) } ?? ""
                }
            }
        }
    }

    private func stepYield(_ delta: Double) {
        yieldText = ServingUnitConverter.format(max(0.5, (servingsYield ?? 1) + delta))
    }

    private func binding(for id: UUID) -> Binding<EditorLine> {
        Binding(
            get: { lines.first { $0.id == id } ?? EditorLine(food: placeholderFood) },
            set: { updated in if let index = lines.firstIndex(where: { $0.id == id }) { lines[index] = updated } }
        )
    }

    private var placeholderFood: NutritionFood {
        NutritionFood.make(userId: viewModel.userId ?? UUID(), name: "", nutrients: NutrientValues(kcal: 0, protein: 0, carbs: 0, fat: 0))
    }

    private func save() {
        guard canSave, let servingsYield,
              let saved = viewModel.saveRecipe(id: recipe?.id, name: name, ingredients: items, servingsYield: servingsYield,
                                               cookedWeightGrams: cookedGrams) else { return }
        onSaved(saved)
        dismiss()
    }
}

/// Always-visible totals strip at the bottom of an editor.
private struct SummaryBar<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .overlay(alignment: .top) { Divider() }
    }
}
