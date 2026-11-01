import SwiftUI

/// Push destination: the add-food flow for one meal.
struct AddFoodRoute: Hashable {
    var slotId: UUID?
    var focusSearch = false
    var query = ""
}

private enum JournalSheet: Identifiable {
    case addMenu, water, targets, settings
    case quickAdd(UUID?), createFood(UUID?), scan(UUID?)
    case editEntry(FoodEntry)

    var id: String {
        switch self {
        case .addMenu: return "addMenu"
        case .water: return "water"
        case .targets: return "targets"
        case .settings: return "settings"
        case .quickAdd: return "quickAdd"
        case .createFood: return "createFood"
        case .scan: return "scan"
        case .editEntry(let entry): return "entry-\(entry.id.uuidString)"
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The nutrition Journal: day header, week strip, macro rings, trackers, one card per meal, water, notes.
struct JournalView: View {
    @ObservedObject var viewModel: NutritionViewModel

    @State private var path: [AddFoodRoute] = []
    @State private var sheet: JournalSheet?
    @State private var pendingSheet: JournalSheet?
    @State private var expanded: Set<UUID> = []
    @State private var macroPage = 0
    @State private var scrolled = false
    @State private var waterExpanded = true
    @State private var showBarcodeSoon = false
    @State private var renaming: MealSlot?
    @State private var renameText = ""
    @State private var creatingMeal = false
    @State private var newMealName = ""

    private let scrollSpace = "journalScroll"

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(spacing: 14) {
                                GeometryReader { proxy in
                                    Color.clear.preference(key: ScrollOffsetKey.self,
                                                           value: proxy.frame(in: .named(scrollSpace)).minY)
                                }
                                .frame(height: 0)
                                JournalWeekStrip(selected: viewModel.date) { viewModel.setDate($0) }
                                macroCard
                                trackerRow
                                mealCards
                                waterCard
                                createMealCard
                                JournalNoteCard(viewModel: viewModel, date: viewModel.date)
                                    .id(JournalFormat.dayId(viewModel.date))
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 16)
                        }
                        .coordinateSpace(name: scrollSpace)
                        .scrollIndicators(.hidden)
                        .onPreferenceChange(ScrollOffsetKey.self) { offset in
                            let isScrolled = offset < -250
                            if isScrolled != scrolled { withAnimation(.easeOut(duration: 0.2)) { scrolled = isScrolled } }
                        }
                        if scrolled {
                            compactCard
                                .padding(.horizontal, 16)
                                .padding(.top, 2)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationDestination(for: AddFoodRoute.self) { route in
                AddFoodFlowView(viewModel: viewModel, route: route)
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if let next = pendingSheet {
                pendingSheet = nil
                sheet = next
            }
        }) { item in
            sheetContent(item)
        }
        .alert("Barcode scanning", isPresented: $showBarcodeSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Coming soon.")
        }
        .alert("Rename meal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Meal name", text: $renameText)
            Button("Save") {
                if let slot = renaming { viewModel.renameMeal(id: slot.id, name: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New meal", isPresented: $creatingMeal) {
            TextField("Meal name", text: $newMealName)
            Button("Add") { viewModel.addMeal(name: newMealName) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { viewModel.reload() }
    }

    /// Swaps one sheet for another once the first has finished dismissing.
    private func present(_ next: JournalSheet) {
        if sheet == nil { sheet = next } else { pendingSheet = next; sheet = nil }
    }

    @ViewBuilder
    private func sheetContent(_ item: JournalSheet) -> some View {
        switch item {
        case .addMenu:
            AddMenuSheet(
                onSearch: { query in
                    sheet = nil
                    path.append(AddFoodRoute(slotId: viewModel.defaultSlotId, focusSearch: true, query: query))
                },
                onWater: { present(.water) },
                onQuickTrack: { present(.quickAdd(viewModel.defaultSlotId)) },
                onCreateFood: { present(.createFood(nil)) }
            )
            .presentationDetents([.medium, .large])
        case .water:
            WaterSheet(viewModel: viewModel).presentationDetents([.medium])
        case .targets:
            NutritionTargetsView(viewModel: viewModel)
        case .settings:
            NutritionSettingsView(viewModel: viewModel)
        case .quickAdd(let slotId):
            QuickAddView(viewModel: viewModel, mealSlotId: slotId)
        case .createFood(let slotId):
            CreateFoodView(viewModel: viewModel, mealSlotId: slotId, logByDefault: false)
        case .scan(let slotId):
            ScanFlowView(viewModel: viewModel, mealSlotId: slotId)
        case .editEntry(let entry):
            EntryEditView(viewModel: viewModel, entry: entry)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack(spacing: 2) {
                Button { viewModel.shiftDay(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous day")
                .accessibilityIdentifier("journal.date.prev")
                Button { viewModel.goToToday() } label: {
                    Text(JournalFormat.title(for: viewModel.date))
                        .font(.title3.weight(.semibold))
                        .minimumScaleFactor(0.8)
                        .frame(minWidth: 96)
                }
                .accessibilityIdentifier("journal.date.label")
                Button { viewModel.shiftDay(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next day")
                .accessibilityIdentifier("journal.date.next")
            }
            .foregroundStyle(AppTheme.textPrimary)
            HStack(spacing: 0) {
                Spacer()
                SideSwitchButton()
                Menu {
                    Button { viewModel.goToToday() } label: { Label("Go to today", systemImage: "calendar") }
                    Button { present(.targets) } label: { Label("Edit targets", systemImage: "target") }
                    Button { present(.settings) } label: { Label("Journal settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("journal.menu.settings")
                } label: {
                    Image(systemName: "ellipsis").font(.headline).foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Journal menu")
                .accessibilityIdentifier("journal.menu")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    // MARK: - Macro card

    private var totals: NutrientValues { viewModel.summary?.totals ?? NutrientValues() }
    private var target: NutritionTarget? { viewModel.summary?.target }

    private struct MacroSpec {
        var name: String, id: String, color: Color, unit: String
        var value: Double, target: Double?
    }

    private var macroSpecs: [MacroSpec] {
        [
            MacroSpec(name: "Protein", id: "protein", color: AppTheme.macroProtein, unit: "grams", value: totals.protein, target: target?.protein),
            MacroSpec(name: "Carbs", id: "carbs", color: AppTheme.macroCarbs, unit: "grams", value: totals.carbs, target: target?.carbs),
            MacroSpec(name: "Fat", id: "fat", color: AppTheme.macroFat, unit: "grams", value: totals.fat, target: target?.fat),
            MacroSpec(name: "kCal", id: "calories", color: AppTheme.macroKcal, unit: "kilocalories", value: totals.kcal, target: target?.kcal)
        ]
    }

    private var macroCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Daily macros").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Menu {
                    Button { present(.targets) } label: { Label("Edit targets", systemImage: "target") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(AppTheme.textPrimary).frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Macro card menu")
                .accessibilityIdentifier("journal.macros.menu")
            }
            TabView(selection: $macroPage) {
                ForEach(0..<3, id: \.self) { page in
                    HStack(spacing: 0) {
                        ForEach(macroSpecs, id: \.id) { spec in ringColumn(spec, page: page) }
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 128)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { page in
                    Circle().fill(page == macroPage ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            if target == nil {
                Button { present(.targets) } label: {
                    Label("Set daily targets", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.targets.set")
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func ringColumn(_ spec: MacroSpec, page: Int) -> some View {
        let value = spec.value
        let goal = spec.target
        let progress = (goal ?? 0) > 0 ? value / (goal ?? 1) : 0
        let primary: String
        let secondary: String
        switch page {
        case 1:
            if let goal { primary = NutritionFormat.whole(abs(goal - value)); secondary = goal - value < 0 ? "over" : "left" }
            else { primary = NutritionFormat.whole(value); secondary = "no goal" }
        case 2:
            primary = goal != nil ? "\(Int((progress * 100).rounded()))%" : "–"
            secondary = goal != nil ? "of goal" : "no goal"
        default:
            primary = NutritionFormat.whole(value)
            secondary = goal.map { "of \(NutritionFormat.whole($0))" } ?? "no goal"
        }
        let spoken: String = {
            guard let goal else { return "\(spec.name), \(NutritionFormat.whole(value)) \(spec.unit), no goal set" }
            let remaining = goal - value
            let tail = remaining < 0 ? "\(NutritionFormat.whole(-remaining)) over" : "\(NutritionFormat.whole(remaining)) remaining"
            return "\(spec.name), \(NutritionFormat.whole(value)) of \(NutritionFormat.whole(goal)) \(spec.unit), \(tail)"
        }()
        return VStack(spacing: 6) {
            Text(spec.name).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
            MacroRing(color: spec.color, progress: progress, primary: primary, secondary: secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(page == 0 ? "journal.ring.\(spec.id)" : "journal.ring.page\(page).\(spec.id)")
    }

    // MARK: - Compact card

    private var compactCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                MiniMacro(letter: "P", icon: nil, color: AppTheme.macroProtein, value: totals.protein, target: target?.protein)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MiniMacro(letter: "C", icon: nil, color: AppTheme.macroCarbs, value: totals.carbs, target: target?.carbs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MiniMacro(letter: "F", icon: nil, color: AppTheme.macroFat, value: totals.fat, target: target?.fat)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MiniMacro(letter: "", icon: "flame", color: AppTheme.macroKcal, value: totals.kcal, target: target?.kcal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 0) {
                ForEach(viewModel.trackers.prefix(3)) { tracker in
                    VStack(spacing: 0) {
                        Text(tracker.nutrient.displayName.replacingOccurrences(of: "Dietary ", with: ""))
                            .font(.caption.weight(.semibold)).foregroundStyle(trackerColor(tracker.nutrient))
                        Text(trackerValueText(tracker.nutrient))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    // MARK: - Trackers

    private func trackerColor(_ nutrient: TrackedNutrient) -> Color {
        switch nutrient {
        case .water: return AppTheme.trackerWater
        case .micro(.fiber): return AppTheme.trackerFiber
        case .micro(.sodium): return AppTheme.trackerSodium
        default: return AppTheme.trackerOther
        }
    }

    private func trackerAmount(_ nutrient: TrackedNutrient) -> Double {
        guard let summary = viewModel.summary else { return 0 }
        return nutrient.amount(in: summary) ?? 0
    }

    private func trackerValueText(_ nutrient: TrackedNutrient) -> String {
        let amount = trackerAmount(nutrient)
        if nutrient == .water { return viewModel.waterUnit.format(ml: amount) }
        return "\(NutritionFormat.amount(amount)) \(nutrient.unit)"
    }

    private var trackerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.trackers) { tracker in
                    trackerCard(tracker)
                }
                addTrackerCard
            }
        }
        .scrollClipDisabled()
    }

    private func trackerCard(_ tracker: NutrientTracker) -> some View {
        let amount = trackerAmount(tracker.nutrient)
        let goal = tracker.dailyTarget
        let progress = (goal ?? 0) > 0 ? min(1, amount / (goal ?? 1)) : 0
        let color = trackerColor(tracker.nutrient)
        return Button { present(.settings) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tracker.nutrient.displayName).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                Text(trackerValueText(tracker.nutrient)).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.2))
                        Capsule().fill(color).frame(width: max(progress > 0 ? 8 : 0, proxy.size.width * progress))
                        if goal != nil {
                            Rectangle().fill(AppTheme.textPrimary).frame(width: 1.5, height: 12)
                                .offset(x: proxy.size.width - 1.5)
                        }
                    }
                }
                .frame(height: 10)
            }
            .padding(12)
            .frame(width: 148, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tracker.nutrient.displayName), \(trackerValueText(tracker.nutrient))")
        .accessibilityIdentifier("journal.tracker.\(tracker.nutrient.storageKey)")
    }

    private var addTrackerCard: some View {
        Menu {
            ForEach(viewModel.availableTrackers) { nutrient in
                Button("Track \(nutrient.displayName)") { viewModel.addTracker(nutrient) }
            }
            Divider()
            Button { present(.settings) } label: { Label("Edit targets", systemImage: "slider.horizontal.3") }
        } label: {
            Image(systemName: "plus").font(.title2).foregroundStyle(AppTheme.textSecondary)
                .frame(width: 70, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppTheme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add tracker")
        .accessibilityIdentifier("journal.tracker.add")
    }

    // MARK: - Meals

    @ViewBuilder
    private var mealCards: some View {
        if let summary = viewModel.summary {
            ForEach(summary.meals) { meal in mealCard(meal) }
            if !summary.unassigned.entries.isEmpty { mealCard(summary.unassigned) }
        }
    }

    private func mealCard(_ meal: MealSummary) -> some View {
        let name = meal.slot?.name ?? "Unassigned"
        let others = viewModel.slots.filter { $0.id != meal.slot?.id }
        return MealCardView(
            name: name, meal: meal, isExpanded: expanded.contains(meal.id), otherMeals: others,
            onToggle: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded.contains(meal.id) { expanded.remove(meal.id) } else { expanded.insert(meal.id) }
                }
            },
            onAdd: { path.append(AddFoodRoute(slotId: meal.slot?.id)) },
            onEditEntry: { sheet = .editEntry($0) },
            onDeleteEntry: { viewModel.delete($0) },
            onRename: {
                guard let slot = meal.slot else { return }
                renameText = slot.name
                renaming = slot
            },
            onClear: { if let id = meal.slot?.id { viewModel.clearMeal(slotId: id) } },
            onMoveAll: { target in meal.entries.forEach { viewModel.move($0, toMeal: target) } },
            onRemove: { if let id = meal.slot?.id { viewModel.archiveMeal(id: id) } }
        )
    }

    private var createMealCard: some View {
        Button {
            newMealName = ""
            creatingMeal = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(.title2)
                Text("Create New Meal").font(.title3.weight(.medium))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journal.meal.create")
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.2)) { waterExpanded.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: waterExpanded ? "chevron.up" : "chevron.down").font(.headline)
                        Text("Water").font(.title2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.water.toggle")
                Spacer()
                RoundPlusButton(id: "journal.water.add", label: "Log water") { sheet = .water }
            }
            Text("Total Logged: \(viewModel.waterUnit.format(ml: viewModel.summary?.waterMl ?? 0))")
                .font(.body).foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("journal.water.total")
            if waterExpanded {
                ForEach(Array(viewModel.waterEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(AppTheme.waterBlue)
                        Text(viewModel.waterUnit.format(ml: entry.amountMl)).foregroundStyle(AppTheme.textPrimary)
                        Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Button { viewModel.deleteWater(entry) } label: {
                            Image(systemName: "trash").foregroundStyle(AppTheme.destructive).frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete water entry")
                        .accessibilityIdentifier("journal.water.delete.\(index)")
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    path.append(AddFoodRoute(slotId: viewModel.defaultSlotId, focusSearch: true))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textPrimary)
                        Text("Food Search").foregroundStyle(AppTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.search")
                Button { showBarcodeSoon = true } label: {
                    Image(systemName: "barcode.viewfinder").font(.title3).foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan barcode")
                .accessibilityIdentifier("journal.barcode")
                Button { sheet = .scan(viewModel.defaultSlotId) } label: {
                    Image(systemName: "camera.viewfinder").font(.title3).foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan nutrition label")
                .accessibilityIdentifier("journal.scan")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)

            Button { sheet = .addMenu } label: {
                Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
            .accessibilityIdentifier("journal.plus")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Week strip

struct JournalWeekStrip: View {
    let selected: Date
    let onSelect: (Date) -> Void

    private var days: [Date] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start else { return [selected] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start)?.startOfDay }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                Button { onSelect(day) } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(AppTheme.macroKcal.opacity(0.35), lineWidth: 3))
                        Circle()
                            .fill(Calendar.current.isDateInToday(day) ? AppTheme.textPrimary : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.textPrimary, lineWidth: isSelected ? 2 : 0)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("journal.day.\(JournalFormat.dayId(day))")
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let step = value.translation.width < 0 ? 7 : -7
                if let next = Calendar.current.date(byAdding: .day, value: step, to: selected) { onSelect(next) }
            }
        )
    }
}

// MARK: - Meal card

private struct MealCardView: View {
    let name: String
    let meal: MealSummary
    let isExpanded: Bool
    let otherMeals: [MealSlot]
    let onToggle: () -> Void
    let onAdd: () -> Void
    let onEditEntry: (FoodEntry) -> Void
    let onDeleteEntry: (FoodEntry) -> Void
    let onRename: () -> Void
    let onClear: () -> Void
    let onMoveAll: (UUID?) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                Button(action: onToggle) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(name).font(.title2.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                            .frame(minHeight: 44, alignment: .leading)
                        MacroChipRow(totals: meal.totals)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.meal.\(name)")
                .accessibilityHint(meal.entries.isEmpty ? "" : (isExpanded ? "Hides entries" : "Shows entries"))
                if meal.slot != nil {
                    Menu {
                        Button(action: onRename) { Label("Rename meal", systemImage: "pencil") }
                        if !meal.entries.isEmpty {
                            Menu {
                                ForEach(otherMeals) { other in
                                    Button(other.name) { onMoveAll(other.id) }
                                }
                            } label: { Label("Move all to…", systemImage: "arrow.right.circle") }
                            Button(role: .destructive, action: onClear) { Label("Clear meal", systemImage: "xmark.bin") }
                        }
                        Button(role: .destructive, action: onRemove) { Label("Remove meal", systemImage: "trash") }
                    } label: {
                        RoundIcon(systemName: "ellipsis")
                    }
                    .accessibilityLabel("\(name) options")
                    .accessibilityIdentifier("journal.meal.\(name).menu")
                }
                RoundPlusButton(id: "journal.meal.\(name).add", label: "Add food to \(name)", action: onAdd)
            }
            if isExpanded && !meal.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(meal.entries) { entry in
                        Divider()
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        Button { onEditEntry(entry) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(NutritionFormat.amount(entry.servings)) × \(entry.servingLabel)")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    MacroSummaryLine(nutrients: entry.total, font: .caption.weight(.semibold))
                }
                Spacer(minLength: 6)
                Text("\(NutritionFormat.whole(entry.total.kcal)) kcal")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journal.entry.\(entry.name)")
        .accessibilityHint("Edit this entry")
        .swipeToDelete(id: "journal.entry.delete") { onDeleteEntry(entry) }
    }
}

// MARK: - Day note

private struct JournalNoteCard: View {
    @ObservedObject var viewModel: NutritionViewModel
    let date: Date
    @State private var text = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day Notes").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            TextField("Add a note about your day…", text: $text, axis: .vertical)
                .lineLimit(3...10)
                .focused($focused)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("journal.note.field")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = viewModel.summary?.note?.text ?? ""
        }
        .onChange(of: viewModel.summary?.note?.text) { _, newValue in
            if !focused, loaded { text = newValue ?? "" }
        }
        .onChange(of: text) { _, _ in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { commit() }
            }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { commit() } }
        .onDisappear { commit() }
    }

    private func commit() {
        saveTask?.cancel()
        guard loaded else { return }
        viewModel.setNote(text, on: date)
    }
}
