import SwiftUI

private enum KitchenSheet: Identifiable {
    case editFood(NutritionFood), createFood, createMeal, createRecipe
    case editMeal(KitchenCollection), editRecipe(KitchenCollection)

    var id: String {
        switch self {
        case .editFood(let food): return "food-\(food.id.uuidString)"
        case .createFood: return "createFood"
        case .createMeal: return "createMeal"
        case .createRecipe: return "createRecipe"
        case .editMeal(let meal): return "meal-\(meal.id.uuidString)"
        case .editRecipe(let recipe): return "recipe-\(recipe.id.uuidString)"
        }
    }
}

/// Saved recipes, meals and foods.
struct KitchenView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var filter: FoodFilter = .all
    @State private var query = ""
    @State private var foods: [NutritionFood] = []
    @State private var collections: [KitchenCollection] = []
    @State private var sheet: KitchenSheet?
    @State private var deleting: KitchenCollection?
    @State private var deletingFood: NutritionFood?

    private var showsFoods: Bool { filter == .all || filter == .foods }
    private var visibleCollections: [KitchenCollection] {
        collections.filter { filter == .all || (filter == .recipes && $0.kind == .recipe) || (filter == .meals && $0.kind == .meal) }
    }
    private var visibleFoods: [NutritionFood] { showsFoods ? foods : [] }
    private var isEmpty: Bool { visibleCollections.isEmpty && visibleFoods.isEmpty }

    private enum Entry: Identifiable {
        case collection(KitchenCollection), food(NutritionFood)
        var id: UUID {
            switch self { case .collection(let c): return c.id; case .food(let f): return f.id }
        }
        var sortName: String {
            switch self { case .collection(let c): return c.name; case .food(let f): return f.name }
        }
    }

    private var entries: [Entry] {
        (visibleCollections.map(Entry.collection) + visibleFoods.map(Entry.food))
            .sorted { $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            NutritionScreenHeader(title: "Kitchen", id: "kitchen.title")
            FoodFilterChips(selection: $filter, idPrefix: "kitchen")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if isEmpty {
                        Text(emptyText)
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("kitchen.empty")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 70) }
                                switch entry {
                                case .collection(let item): collectionRow(item)
                                case .food(let food): row(food)
                                }
                            }
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                PillSearchField(text: $query, prompt: "Search kitchen", id: "kitchen.search")
                Menu {
                    Button { sheet = .createFood } label: { Label("Create food", systemImage: KitchenIcon.food) }
                        .accessibilityIdentifier("kitchen.create.food")
                    Button { sheet = .createMeal } label: { Label("Create meal", systemImage: KitchenIcon.meal) }
                        .accessibilityIdentifier("kitchen.create.meal")
                    Button { sheet = .createRecipe } label: { Label("Create recipe", systemImage: KitchenIcon.recipe) }
                        .accessibilityIdentifier("kitchen.create.recipe")
                } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
                }
                .accessibilityLabel("Create")
                .accessibilityIdentifier("kitchen.create")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .editFood(let food): FoodEditView(viewModel: viewModel, food: food)
            case .createFood: CreateFoodView(viewModel: viewModel, logByDefault: false)
            case .createMeal: MealEditorView(viewModel: viewModel)
            case .createRecipe: RecipeEditorView(viewModel: viewModel)
            case .editMeal(let meal): MealEditorView(viewModel: viewModel, meal: meal)
            case .editRecipe(let recipe): RecipeEditorView(viewModel: viewModel, recipe: recipe)
            }
        }
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = deleting {
                    if item.kind == .meal { viewModel.deleteMeal(item) } else { viewModel.deleteRecipe(item) }
                }
                deleting = nil
                reload()
            }
            .accessibilityIdentifier("kitchen.delete.confirm")
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Entries you already logged stay in your journal.") }
        .alert("Delete \(deletingFood?.name ?? "")?", isPresented: Binding(get: { deletingFood != nil }, set: { if !$0 { deletingFood = nil } })) {
            Button("Delete", role: .destructive) {
                if let food = deletingFood { viewModel.deleteFood(food) }
                deletingFood = nil
                reload()
            }
            .accessibilityIdentifier("kitchen.delete.confirm")
            Button("Cancel", role: .cancel) { deletingFood = nil }
        } message: { Text("Entries you already logged stay in your journal.") }
        .onAppear(perform: reload)
        .onChange(of: query) { _, _ in reload() }
        .onChange(of: viewModel.foodsVersion) { _, _ in reload() }
        .onChange(of: viewModel.kitchenVersion) { _, _ in reload() }
    }

    private var emptyText: String {
        if !query.isEmpty { return "Nothing in your Kitchen matches." }
        switch filter {
        case .recipes: return "No recipes yet. Tap + to create one."
        case .meals: return "No saved meals yet. Tap + to create one, or save a meal from your Journal."
        default: return "Your Kitchen is empty. Tap + to create a food, meal or recipe, or scan a label from the Journal."
        }
    }

    private func collectionRow(_ item: KitchenCollection) -> some View {
        let open = { sheet = item.kind == .meal ? .editMeal(item) : .editRecipe(item) }
        return CollectionRowView(item: item) { EmptyView() }
            .background(AppTheme.surface)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("kitchen.row.\(item.name)")
            .swipeToDelete(id: "kitchen.swipeDelete.\(item.name)", onTap: open) { deleting = item }
    }

    private func row(_ food: NutritionFood) -> some View {
        HStack(spacing: 0) {
            KitchenFoodRow(food: food) { EmptyView() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("kitchen.food.\(food.name)")
            Button { viewModel.setFavorite(food, !food.isFavorite) } label: {
                Image(systemName: food.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(food.isFavorite ? AppTheme.warning : AppTheme.textSecondary)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(food.isFavorite ? "Remove \(food.name) from favourites" : "Add \(food.name) to favourites")
            .accessibilityIdentifier("kitchen.favorite.\(food.name)")
        }
        .background(AppTheme.surface)
        .swipeToDelete(id: "kitchen.swipeDelete.\(food.name)", onTap: { sheet = .editFood(food) }) { deletingFood = food }
    }

    private func reload() {
        // A recipe's own food shows up as the recipe, never under Foods.
        foods = viewModel.searchFoods(query).filter { $0.source != .recipe }
        collections = viewModel.kitchenItems(query: query)
    }
}

/// Edit or delete a saved food (name, serving, per-serving macros, favourite).
struct FoodEditView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let food: NutritionFood
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var servingLabel = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var favourite = false
    @State private var loaded = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && NutritionFormat.parse(kcal) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).frame(minHeight: 44).accessibilityIdentifier("kitchen.edit.name")
                    TextField("Serving (e.g. 1 cup)", text: $servingLabel).frame(minHeight: 44)
                        .accessibilityIdentifier("kitchen.edit.serving")
                    Toggle("Favourite", isOn: $favourite).tint(AppTheme.accent)
                        .accessibilityIdentifier("kitchen.edit.favourite")
                }
                .listRowBackground(AppTheme.surface)
                if food.isAIEstimate {
                    Section {
                        AIEstimateBadge()
                        if let confidence = food.aiConfidence {
                            Text("Confidence: \(confidence.rawValue)").font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        }
                        AISourceLinks(sources: food.aiSources, idPrefix: "kitchen.edit.source")
                    } header: { Text("Estimated by AI") }
                    .listRowBackground(AppTheme.surface)
                }
                Section {
                    NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "kitchen.edit.kcal")
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "kitchen.edit.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "kitchen.edit.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "kitchen.edit.fat")
                } header: { Text("Per serving") }
                .listRowBackground(AppTheme.surface)
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteFood(food)
                        dismiss()
                    } label: { Label("Delete food", systemImage: "trash").frame(minHeight: 44) }
                    .accessibilityIdentifier("kitchen.edit.delete")
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("kitchen.edit.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = food.name
                servingLabel = food.servingLabel
                kcal = NutritionFormat.field(food.nutrients.kcal)
                protein = NutritionFormat.field(food.nutrients.protein)
                carbs = NutritionFormat.field(food.nutrients.carbs)
                fat = NutritionFormat.field(food.nutrients.fat)
                favourite = food.isFavorite
            }
        }
        .keyboardDoneButton()
    }

    private func save() {
        var updated = food
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { updated.servingLabel = label }
        updated.nutrients.kcal = max(0, NutritionFormat.parse(kcal) ?? food.nutrients.kcal)
        updated.nutrients.protein = max(0, NutritionFormat.parse(protein) ?? 0)
        updated.nutrients.carbs = max(0, NutritionFormat.parse(carbs) ?? 0)
        updated.nutrients.fat = max(0, NutritionFormat.parse(fat) ?? 0)
        updated.isFavorite = favourite
        viewModel.updateFood(updated)
        dismiss()
    }
}
