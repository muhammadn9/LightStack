import SwiftUI

/// Pick one of your own saved foods (recent, favourites, or search) and log it.
struct AddFoodView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case recent = "Recent", favourites = "Favourites"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .recent
    @State private var query = ""
    @State private var foods: [NutritionFood] = []
    @State private var path: [UUID] = []

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
                            .accessibilityHidden(true)
                        TextField("Search your foods", text: $query)
                            .frame(minHeight: 44)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("nutrition.history.search")
                    }
                    if !isSearching {
                        Picker("Show", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("nutrition.addFood.mode")
                    }
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    if foods.isEmpty {
                        Text(emptyText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("nutrition.addFood.empty")
                    }
                    ForEach(foods) { food in
                        HStack(spacing: 8) {
                            Button { path.append(food.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(food.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text("\(food.servingLabel) · \(NutritionFormat.whole(food.nutrients.kcal)) kcal")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("nutrition.food.\(food.id.uuidString)")

                            Button {
                                viewModel.setFavorite(food, !food.isFavorite)
                                refresh()
                            } label: {
                                Image(systemName: food.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(food.isFavorite ? AppTheme.accent : AppTheme.textSecondary)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(food.isFavorite ? "Remove \(food.name) from favourites" : "Add \(food.name) to favourites")
                            .accessibilityIdentifier("nutrition.food.favorite.\(food.id.uuidString)")
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .navigationDestination(for: UUID.self) { id in
                if let food = viewModel.searchFoods("").first(where: { $0.id == id }) ?? foods.first(where: { $0.id == id }) {
                    LogFoodView(viewModel: viewModel, food: food) { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: query) { _, _ in refresh() }
            .onChange(of: mode) { _, _ in refresh() }
        }
    }

    private var emptyText: String {
        if isSearching { return "No saved foods match." }
        switch mode {
        case .recent: return "Foods you log will show up here. Scan a label to save one."
        case .favourites: return "Tap the star on a food to keep it here."
        }
    }

    private func refresh() {
        if isSearching { foods = viewModel.searchFoods(query) }
        else {
            switch mode {
            case .recent: foods = viewModel.recentFoods()
            case .favourites: foods = viewModel.favoriteFoods()
            }
        }
    }
}

// MARK: - Log a saved food

/// Pick a quantity and unit; converts to servings where the units are comparable.
struct LogFoodView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let food: NutritionFood
    let onLogged: () -> Void

    @State private var quantity = "1"
    @State private var unit: ServingChoice = .servings

    /// A unit the quantity can be entered in.
    enum ServingChoice: Hashable, Identifiable {
        case servings
        case unit(NutritionUnit)
        var id: String {
            switch self {
            case .servings: return "servings"
            case .unit(let u): return u.rawValue
            }
        }
    }

    private var foodUnit: NutritionUnit? { NutritionUnit(rawValue: food.servingUnit) }

    private var choices: [ServingChoice] {
        var result: [ServingChoice] = [.servings]
        for candidate in NutritionUnit.allCases where candidate != .serving {
            if candidate == foodUnit || conversionBase(for: candidate) != nil { result.append(.unit(candidate)) }
        }
        return result
    }

    private var foodGrams: Double? { food.servingGrams ?? foodUnit?.grams(forQuantity: food.servingAmount) }
    private var foodMl: Double? { foodUnit?.millilitres(forQuantity: food.servingAmount) }

    /// Amount of the food's serving expressed in `candidate`'s dimension, if comparable.
    private func conversionBase(for candidate: NutritionUnit) -> Double? {
        if candidate == foodUnit, food.servingAmount > 0 { return food.servingAmount }
        if candidate.gramsPerUnit != nil, let g = foodGrams, g > 0 { return g / (candidate.gramsPerUnit ?? 1) }
        if candidate.millilitresPerUnit != nil, let ml = foodMl, ml > 0 { return ml / (candidate.millilitresPerUnit ?? 1) }
        return nil
    }

    private var servings: Double? {
        guard let q = NutritionFormat.parse(quantity), q > 0 else { return nil }
        switch unit {
        case .servings: return q
        case .unit(let u):
            guard let base = conversionBase(for: u), base > 0 else { return nil }
            return q / base
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                    Text("Per \(food.servingLabel)").font(.footnote).foregroundStyle(AppTheme.textSecondary)
                }
                HStack(spacing: 14) {
                    stat("kcal", food.nutrients.kcal)
                    stat("P", food.nutrients.protein)
                    stat("C", food.nutrients.carbs)
                    stat("F", food.nutrients.fat)
                }
            }
            .listRowBackground(AppTheme.surface)

            Section {
                NutritionField(title: "Amount", unit: "", text: $quantity, id: "nutrition.log.quantity", placeholder: "1")
                Picker("Unit", selection: $unit) {
                    ForEach(choices) { choice in
                        Text(label(for: choice)).tag(choice)
                    }
                }
                .accessibilityIdentifier("nutrition.log.unit")
                if let servings {
                    let scaled = food.nutrients.scaled(by: servings)
                    Text("\(NutritionFormat.amount(servings)) serving(s) · \(NutritionFormat.whole(scaled.kcal)) kcal")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("nutrition.log.summary")
                }
            } header: {
                Text("How much")
            }
            .listRowBackground(AppTheme.surface)
        }
        .nutritionFormStyle()
        .navigationTitle("Log food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") {
                    guard let servings else { return }
                    viewModel.log(food, servings: servings)
                    onLogged()
                }
                .disabled(servings == nil)
                .accessibilityIdentifier("nutrition.log.confirm")
            }
        }
    }

    private func label(for choice: ServingChoice) -> String {
        switch choice {
        case .servings: return "serving"
        case .unit(let u): return u.displayName
        }
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(NutritionFormat.whole(value)).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

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
        viewModel.update(updated)
        dismiss()
    }
}
