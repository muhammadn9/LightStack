import SwiftUI

private enum FlowSheet: Identifiable {
    case servings(NutritionFood), plate, quickAdd, create, scan, barcode, ai
    case branded(OpenFoodFactsProduct)
    case meal(KitchenCollection)

    var id: String {
        switch self {
        case .servings(let food): return "servings-\(food.id.uuidString)"
        case .plate: return "plate"
        case .quickAdd: return "quickAdd"
        case .create: return "create"
        case .scan: return "scan"
        case .barcode: return "barcode"
        case .ai: return "ai"
        case .branded(let p): return "branded-\(p.barcode)"
        case .meal(let m): return "meal-\(m.id.uuidString)"
        }
    }
}

/// Pick several saved foods onto a "plate", then log them all into one meal with one tap.
struct AddFoodFlowView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let route: AddFoodRoute
    @Environment(\.dismiss) private var dismiss

    @State private var slotId: UUID?
    @State private var plate: [PlateItem] = []
    @State private var filter: FoodFilter = .all
    @State private var query = ""
    @State private var showAllRecent = false
    @State private var recent: [NutritionFood] = []
    @State private var saved: [NutritionFood] = []
    @State private var results: [NutritionFood] = []
    @State private var meals: [KitchenCollection] = []
    @State private var sheet: FlowSheet?
    @State private var popAfterSheet = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var slotName: String { viewModel.slot(id: slotId)?.name ?? "Meal" }
    private var showsMeals: Bool { filter == .all || filter == .meals }
    private var showsFoodList: Bool { filter != .meals }

    private func matchesFilter(_ food: NutritionFood) -> Bool {
        switch filter {
        case .all: return true
        case .recipes: return food.source == .recipe
        case .foods: return food.source != .recipe
        case .meals: return false
        }
    }

    private var visibleResultsEmpty: Bool {
        (!showsFoodList || results.filter(matchesFilter).isEmpty) && (!showsMeals || meals.isEmpty)
    }

    private var emptyListText: String {
        switch filter {
        case .recipes: return "No recipes yet. Create one from the + menu in the Journal or the Kitchen."
        case .meals: return "No saved meals yet. Save a meal from the plate or from a Journal meal."
        default: return "Foods you save show up here. Tap + to create one, scan a label or use Quick add."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FoodFilterChips(selection: $filter, idPrefix: "addfood")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isSearching {
                        if showsMeals && !meals.isEmpty { mealsSection }
                        if showsFoodList {
                            let foodResults = results.filter(matchesFilter)
                            if !foodResults.isEmpty || meals.isEmpty || !showsMeals {
                                section(title: "Results", foods: foodResults, icon: "magnifyingglass")
                            }
                        }
                        if visibleResultsEmpty {
                            Text(filter == .meals ? "No saved meals match." : "No saved foods match.")
                                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .accessibilityIdentifier("addfood.empty")
                        }
                        if filter == .all || filter == .foods {
                            BrandedResultsSection(
                                state: viewModel.brandedState,
                                onSelect: { sheet = .branded($0) },
                                onRetry: { viewModel.searchBranded(query) }
                            )
                        }
                    } else {
                        let recentShown = recent.filter(matchesFilter)
                        let savedShown = saved.filter(matchesFilter)
                        if showsFoodList && !recentShown.isEmpty {
                            section(title: "Most Recent", foods: showAllRecent ? recentShown : Array(recentShown.prefix(5)),
                                    icon: "clock.arrow.circlepath", showMore: !showAllRecent && recentShown.count > 5)
                        }
                        if showsMeals && !meals.isEmpty { mealsSection }
                        if showsFoodList && !savedShown.isEmpty {
                            section(title: "Saved", foods: savedShown, icon: "bookmark")
                        }
                        if recentShown.isEmpty && savedShown.isEmpty && (meals.isEmpty || !showsMeals) {
                            Text(emptyListText)
                                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .accessibilityIdentifier("addfood.empty")
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $sheet, onDismiss: {
            if popAfterSheet { popAfterSheet = false; dismiss() }
        }) { item in
            sheetContent(item)
        }
        .onAppear {
            if slotId == nil { slotId = route.slotId ?? viewModel.defaultSlotId }
            if query.isEmpty { query = route.query }
            reloadFoods()
            updateBranded()
            if route.focusSearch {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    searchFocused = true
                }
            }
        }
        .onChange(of: query) { _, _ in reloadFoods(); updateBranded() }
        .onDisappear { viewModel.cancelBrandedSearch() }
        .onChange(of: viewModel.foodsVersion) { _, _ in reloadFoods() }
        .onChange(of: viewModel.kitchenVersion) { _, _ in reloadFoods() }
    }

    // MARK: - Header

    private var plateCalories: Double { plate.reduce(0) { $0 + $1.food.nutrients.kcal * $1.servings } }

    private var header: some View {
        let base = viewModel.summary?.totals.kcal ?? 0
        let current = base + plateCalories
        let goal = viewModel.summary?.target?.kcal
        let progress = (goal ?? 0) > 0 ? min(1, current / (goal ?? 1)) : 0
        return HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("addfood.back")

            VStack(alignment: .leading, spacing: 1) {
                Menu {
                    ForEach(viewModel.slots) { slot in
                        Button { slotId = slot.id } label: {
                            if slot.id == slotId { Label(slot.name, systemImage: "checkmark") } else { Text(slot.name) }
                        }
                        .accessibilityIdentifier("addfood.meal.\(slot.name)")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(slotName).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                }
                .accessibilityLabel("Meal: \(slotName)")
                .accessibilityIdentifier("addfood.mealPicker")
                Text(viewModel.date.formatted(.dateTime.weekday(.abbreviated).month(.wide).day()))
                    .font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "flame").imageScale(.small)
                    Text(goal.map { "\(NutritionFormat.whole(current)) / \(NutritionFormat.whole($0))" }
                         ?? NutritionFormat.whole(current))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.macroTint(AppTheme.macroKcal))
                        Capsule().fill(AppTheme.macroKcal).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories \(NutritionFormat.whole(current))" + (goal.map { " of \(NutritionFormat.whole($0))" } ?? ""))
            .accessibilityIdentifier("addfood.calories")

            Spacer(minLength: 0)
            platePill
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .background(AppTheme.surface)
    }

    private var platePill: some View {
        HStack(spacing: 0) {
            Button { sheet = .plate } label: {
                HStack(spacing: 6) {
                    Image(systemName: "circle.dashed.inset.filled").foregroundStyle(AppTheme.textSecondary)
                    Text("\(plate.count)").font(.headline).foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.leading, 12).padding(.trailing, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plate, \(plate.count) items")
            .accessibilityIdentifier("plate.open")
            Button { confirmPlate() } label: {
                Image(systemName: "checkmark").font(.headline.weight(.bold))
                    .foregroundStyle(plate.isEmpty ? AppTheme.textSecondary : AppTheme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(plate.isEmpty ? AppTheme.surfaceElevated : AppTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(plate.isEmpty)
            .accessibilityLabel("Log plate")
            .accessibilityIdentifier("plate.confirm")
        }
        .background(AppTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 0.5))
    }

    // MARK: - Sections and rows

    private func section(title: String, foods: [NutritionFood], icon: String, showMore: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(AppTheme.textSecondary)
                Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                    if index > 0 { Divider().padding(.leading, 70) }
                    foodRow(food)
                }
                if showMore {
                    Divider()
                    Button { withAnimation { showAllRecent = true } } label: {
                        Text("Show more results").font(.body.weight(.medium)).foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addfood.showMore")
                }
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: KitchenIcon.meal).foregroundStyle(AppTheme.textSecondary)
                Text("Meals").font(.headline).foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    if index > 0 { Divider().padding(.leading, 70) }
                    Button { sheet = .meal(meal) } label: {
                        CollectionRowView(item: meal, showBadge: true) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addfood.savedMeal.\(meal.name)")
                    .accessibilityHint("Review and log this meal")
                }
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func foodRow(_ food: NutritionFood) -> some View {
        let inPlate = plate.contains { $0.food.id == food.id }
        return HStack(spacing: 0) {
            Button { sheet = .servings(food) } label: {
                FoodRowView(food: food) { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addfood.food.\(food.name)")
            .accessibilityHint("Adjust servings")
            Button { togglePlate(food) } label: {
                Image(systemName: inPlate ? "checkmark" : "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(inPlate ? AppTheme.onAccent : AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(inPlate ? AppTheme.accent : AppTheme.accent.opacity(0.16), in: Circle())
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inPlate ? "Remove \(food.name) from plate" : "Add \(food.name) to plate")
            .accessibilityIdentifier("addfood.add.\(food.name)")
        }
    }

    private func addToPlate(_ food: NutritionFood, _ servings: Double) {
        if let index = plate.firstIndex(where: { $0.food.id == food.id }) { plate[index].servings = servings }
        else { plate.append(PlateItem(food: food, servings: servings)) }
    }

    private func togglePlate(_ food: NutritionFood) {
        if let index = plate.firstIndex(where: { $0.food.id == food.id }) {
            plate.remove(at: index)
        } else {
            plate.append(PlateItem(food: food))
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PillSearchField(text: $query, prompt: "Search food", id: "addfood.search", focus: $searchFocused)
            Button { sheet = .barcode } label: {
                Image(systemName: "barcode.viewfinder").font(.title3).foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
            }
            .accessibilityLabel("Scan barcode")
            .accessibilityIdentifier("addfood.barcode")
            Menu {
                Button { sheet = .ai } label: { Label("Ask AI", systemImage: "sparkles") }
                    .accessibilityIdentifier("addfood.ai")
                Button { sheet = .create } label: { Label("Create food", systemImage: "carrot") }
                    .accessibilityIdentifier("addfood.create")
                Button { sheet = .quickAdd } label: { Label("Quick add", systemImage: "bolt") }
                    .accessibilityIdentifier("addfood.quickadd")
                Button { sheet = .scan } label: { Label("Scan label", systemImage: "camera.viewfinder") }
                    .accessibilityIdentifier("addfood.scan")
            } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
            }
            .accessibilityLabel("More ways to add")
            .accessibilityIdentifier("addfood.plus")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background.opacity(0.95))
    }

    // MARK: - Actions

    private func confirmPlate() {
        guard !plate.isEmpty else { return }
        viewModel.logPlate(plate, mealSlotId: slotId)
        dismiss()
    }

    private func updateBranded() {
        if isSearching { viewModel.searchBranded(query) } else { viewModel.cancelBrandedSearch() }
    }

    private func reloadFoods() {
        meals = viewModel.savedMeals(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        if isSearching {
            results = viewModel.searchFoods(query)
        } else {
            let recents = viewModel.recentFoods(limit: 50)
            recent = recents
            let recentIds = Set(recents.map(\.id))
            saved = viewModel.searchFoods("").filter { !recentIds.contains($0.id) }
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: FlowSheet) -> some View {
        switch item {
        case .servings(let food):
            let existing = plate.first { $0.food.id == food.id }
            ServingsSheet(
                food: food, units: viewModel.servingUnits(for: food),
                initial: existing?.servings ?? 1, initialUnit: existing?.unit, initialAmount: existing?.amount,
                isOnPlate: existing != nil,
                onSave: { item in
                    if let index = plate.firstIndex(where: { $0.food.id == food.id }) { plate[index] = item }
                    else { plate.append(item) }
                },
                onRemove: { plate.removeAll { $0.food.id == food.id } }
            )
            .presentationDetents([.medium])
        case .plate:
            PlateSheet(viewModel: viewModel, plate: $plate).presentationDetents([.medium, .large])
        case .meal(let meal):
            MealLogSheet(viewModel: viewModel, meal: meal, slotName: slotName, slotId: slotId,
                         onLogged: { popAfterSheet = true })
                .presentationDetents([.medium, .large])
        case .quickAdd:
            QuickAddView(viewModel: viewModel, mealSlotId: slotId, onAdded: { popAfterSheet = true })
        case .create:
            CreateFoodView(viewModel: viewModel, mealSlotId: slotId, logByDefault: true, onLogged: { popAfterSheet = true })
        case .scan:
            ScanFlowView(viewModel: viewModel, mealSlotId: slotId, onLogged: { popAfterSheet = true })
        case .barcode:
            BarcodeFlowView(viewModel: viewModel, mealSlotId: slotId,
                            onPlate: { food, servings in addToPlate(food, servings) },
                            onLogged: { popAfterSheet = true })
        case .ai:
            AIMealLogView(viewModel: viewModel, initialText: query, initialSlotId: slotId,
                          onLogged: { popAfterSheet = true })
        case .branded(let product):
            NavigationStack {
                BrandedServingView(
                    target: ServingTarget(product: product), mealName: slotName,
                    onAdd: { servings in
                        viewModel.saveBrandedFood(product, logServings: servings, mealSlotId: slotId)
                        popAfterSheet = true
                        sheet = nil
                    },
                    onPlate: { servings in
                        if let food = viewModel.saveBrandedFood(product) { addToPlate(food, servings) }
                        sheet = nil
                    }
                )
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sheet = nil } } }
            }
        }
    }
}

// MARK: - Servings sheet

private struct ServingsSheet: View {
    let food: NutritionFood
    let units: [NutritionUnit]
    let initial: Double
    let initialUnit: NutritionUnit?
    let initialAmount: Double?
    let isOnPlate: Bool
    let onSave: (PlateItem) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unit: NutritionUnit = .serving
    @State private var loaded = false

    private var amount: Double? { NutritionFormat.parse(text).flatMap { $0 > 0 ? $0 : nil } }
    private var servings: Double? {
        amount.flatMap { ServingUnitConverter.servings(amount: $0, unit: unit, for: food) }.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text(JournalFormat.emoji(for: food.name)).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                            Text("Per \(food.servingLabel)").font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
                Section {
                    NutritionField(title: units.count > 1 ? "Amount" : "Servings", unit: unit == .serving ? "" : unit.displayName,
                                   text: $text, id: "plate.servings.field", placeholder: "1")
                    if units.count > 1 { unitPicker }
                    if let servings {
                        MacroSummaryLine(nutrients: food.nutrients.scaled(by: servings))
                            .accessibilityIdentifier("plate.servings.summary")
                        if unit != .serving {
                            Text("= \(ServingUnitConverter.format(servings)) \(servings == 1 ? "serving" : "servings")")
                                .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
                if isOnPlate {
                    Section {
                        Button(role: .destructive) { onRemove(); dismiss() } label: {
                            Label("Remove from plate", systemImage: "minus.circle").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("plate.servings.remove")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .nutritionFormStyle()
            .navigationTitle(isOnPlate ? "Servings" : "Add to plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isOnPlate ? "Update" : "Add") {
                        guard let servings, let amount else { return }
                        onSave(PlateItem(food: food, servings: servings, unit: unit == .serving ? nil : unit,
                                         amount: unit == .serving ? nil : amount))
                        dismiss()
                    }
                    .disabled(servings == nil)
                    .accessibilityIdentifier("plate.servings.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let initialUnit, let initialAmount, units.contains(initialUnit) {
                    unit = initialUnit
                    text = ServingUnitConverter.format(initialAmount)
                } else {
                    text = ServingUnitConverter.format(initial)
                }
            }
        }
    }

    /// Unit chips, favourites first.
    private var unitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(units) { option in
                    Button { select(option) } label: {
                        Text(option.displayName)
                            .font(.subheadline.weight(unit == option ? .semibold : .regular))
                            .foregroundStyle(unit == option ? AppTheme.onAccent : AppTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(unit == option ? AppTheme.accent : AppTheme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(unit == option ? .isSelected : [])
                    .accessibilityIdentifier("log.unit.\(option.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.unit")
    }

    private func select(_ option: NutritionUnit) {
        guard option != unit else { return }
        if let amount, let converted = ServingUnitConverter.convert(amount, from: unit, to: option, for: food) {
            text = ServingUnitConverter.format(converted)
        }
        unit = option
    }
}

// MARK: - Plate sheet

private struct PlateSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Binding var plate: [PlateItem]
    @Environment(\.dismiss) private var dismiss
    @State private var savingAsMeal = false

    var body: some View {
        NavigationStack {
            List {
                if plate.isEmpty {
                    Text("Tap + on a food to put it on your plate.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(AppTheme.surface)
                }
                ForEach($plate, id: \.food.id) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.food.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            HStack(spacing: 0) {
                                Button { item.servings = max(0.5, item.servings - 0.5); item.unit = nil; item.amount = nil } label: {
                                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Fewer servings of \(item.food.name)")
                                .accessibilityIdentifier("plate.item.\(item.food.name).dec")
                                Text(item.measuredLabel ?? NutritionFormat.amount(item.servings))
                                    .font(.headline).frame(minWidth: 36)
                                    .accessibilityIdentifier("plate.item.\(item.food.name).servings")
                                Button { item.servings += 0.5; item.unit = nil; item.amount = nil } label: {
                                    Image(systemName: "plus.circle").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("More servings of \(item.food.name)")
                                .accessibilityIdentifier("plate.item.\(item.food.name).inc")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(AppTheme.accent)
                        }
                        MacroSummaryLine(nutrients: item.food.nutrients.scaled(by: item.servings), font: .caption.weight(.semibold))
                    }
                    .listRowBackground(AppTheme.surface)
                }
                .onDelete { plate.remove(atOffsets: $0) }
                if !plate.isEmpty {
                    Button { savingAsMeal = true } label: {
                        Label("Save as meal", systemImage: "square.and.arrow.down").foregroundStyle(AppTheme.accent).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("plate.saveAsMeal")
                    .listRowBackground(AppTheme.surface)
                }
            }
            .sheet(isPresented: $savingAsMeal) {
                MealEditorView(viewModel: viewModel, initialItems: plate)
            }
            .nutritionFormStyle()
            .navigationTitle("Plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("plate.done") }
            }
        }
    }
}
