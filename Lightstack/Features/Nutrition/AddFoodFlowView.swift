import SwiftUI

private enum FlowSheet: Identifiable {
    case servings(NutritionFood), plate, quickAdd, create, scan

    var id: String {
        switch self {
        case .servings(let food): return "servings-\(food.id.uuidString)"
        case .plate: return "plate"
        case .quickAdd: return "quickAdd"
        case .create: return "create"
        case .scan: return "scan"
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
    @State private var sheet: FlowSheet?
    @State private var popAfterSheet = false
    @State private var showBarcodeSoon = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var slotName: String { viewModel.slot(id: slotId)?.name ?? "Meal" }

    var body: some View {
        VStack(spacing: 0) {
            header
            FoodFilterChips(selection: $filter, idPrefix: "addfood")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if filter == .recipes || filter == .meals {
                        Text("\(filter.rawValue) are coming soon. Save foods to your Kitchen in the meantime.")
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("addfood.soon")
                    } else if isSearching {
                        section(title: "Results", foods: results, icon: "magnifyingglass")
                        if results.isEmpty {
                            Text("No saved foods match.").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .accessibilityIdentifier("addfood.empty")
                        }
                    } else {
                        if !recent.isEmpty {
                            section(title: "Most Recent", foods: showAllRecent ? recent : Array(recent.prefix(5)),
                                    icon: "clock.arrow.circlepath", showMore: !showAllRecent && recent.count > 5)
                        }
                        if !saved.isEmpty {
                            section(title: "Saved", foods: saved, icon: "bookmark")
                        }
                        if recent.isEmpty && saved.isEmpty {
                            Text("Foods you save show up here. Tap + to create one, scan a label or use Quick add.")
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
        .alert("Barcode scanning", isPresented: $showBarcodeSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Coming soon.")
        }
        .onAppear {
            if slotId == nil { slotId = route.slotId ?? viewModel.defaultSlotId }
            if query.isEmpty { query = route.query }
            reloadFoods()
            if route.focusSearch {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    searchFocused = true
                }
            }
        }
        .onChange(of: query) { _, _ in reloadFoods() }
        .onChange(of: viewModel.foodsVersion) { _, _ in reloadFoods() }
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
            Button { showBarcodeSoon = true } label: {
                Image(systemName: "barcode.viewfinder").font(.title3).foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
            }
            .accessibilityLabel("Scan barcode")
            .accessibilityIdentifier("addfood.barcode")
            Menu {
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

    private func reloadFoods() {
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
                food: food, initial: existing?.servings ?? 1, isOnPlate: existing != nil,
                onSave: { servings in
                    if let index = plate.firstIndex(where: { $0.food.id == food.id }) { plate[index].servings = servings }
                    else { plate.append(PlateItem(food: food, servings: servings)) }
                },
                onRemove: { plate.removeAll { $0.food.id == food.id } }
            )
            .presentationDetents([.medium])
        case .plate:
            PlateSheet(plate: $plate).presentationDetents([.medium, .large])
        case .quickAdd:
            QuickAddView(viewModel: viewModel, mealSlotId: slotId, onAdded: { popAfterSheet = true })
        case .create:
            CreateFoodView(viewModel: viewModel, mealSlotId: slotId, logByDefault: true, onLogged: { popAfterSheet = true })
        case .scan:
            ScanFlowView(viewModel: viewModel, mealSlotId: slotId, onLogged: { popAfterSheet = true })
        }
    }
}

// MARK: - Servings sheet

private struct ServingsSheet: View {
    let food: NutritionFood
    let initial: Double
    let isOnPlate: Bool
    let onSave: (Double) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var servings: Double? { NutritionFormat.parse(text).flatMap { $0 > 0 ? $0 : nil } }

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
                    NutritionField(title: "Servings", unit: "", text: $text, id: "plate.servings.field", placeholder: "1")
                    if let servings {
                        MacroSummaryLine(nutrients: food.nutrients.scaled(by: servings))
                            .accessibilityIdentifier("plate.servings.summary")
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
                        guard let servings else { return }
                        onSave(servings)
                        dismiss()
                    }
                    .disabled(servings == nil)
                    .accessibilityIdentifier("plate.servings.save")
                }
            }
            .onAppear { text = NutritionFormat.amount(initial) }
        }
    }
}

// MARK: - Plate sheet

private struct PlateSheet: View {
    @Binding var plate: [PlateItem]
    @Environment(\.dismiss) private var dismiss

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
                                Button { item.servings = max(0.5, item.servings - 0.5) } label: {
                                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Fewer servings of \(item.food.name)")
                                .accessibilityIdentifier("plate.item.\(item.food.name).dec")
                                Text(NutritionFormat.amount(item.servings))
                                    .font(.headline).frame(minWidth: 36)
                                    .accessibilityIdentifier("plate.item.\(item.food.name).servings")
                                Button { item.servings += 0.5 } label: {
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
