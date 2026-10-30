import SwiftUI

/// Creates the view model once the environment is available, then shows the day view.
struct NutritionTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var viewModel: NutritionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                NutritionDayView(viewModel: viewModel)
            } else {
                AppTheme.background.ignoresSafeArea()
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = environment.makeNutritionViewModel() }
        }
    }
}

// MARK: - Day view

private enum NutritionSheet: Identifiable {
    case quickAdd, addFood, scan, targets
    case editEntry(FoodEntry)

    var id: String {
        switch self {
        case .quickAdd: return "quickAdd"
        case .addFood: return "addFood"
        case .scan: return "scan"
        case .targets: return "targets"
        case .editEntry(let entry): return "entry-\(entry.id.uuidString)"
        }
    }
}

struct NutritionDayView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var sheet: NutritionSheet?
    @State private var microsExpanded = false

    var body: some View {
        NavigationStack {
            List {
                dateSwitcher
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                summaryCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                actionButtons
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                microsCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                entriesSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .targets } label: {
                        Label("Targets", systemImage: "target")
                    }
                    .accessibilityIdentifier("nutrition.target.edit")
                }
            }
            .onAppear { viewModel.reload() }
            .sheet(item: $sheet) { item in
                sheetContent(item)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: NutritionSheet) -> some View {
        switch item {
        case .quickAdd:
            QuickAddView(viewModel: viewModel)
        case .addFood:
            AddFoodView(viewModel: viewModel)
        case .scan:
            ScanFlowView(viewModel: viewModel)
        case .targets:
            NutritionTargetsView(viewModel: viewModel)
        case .editEntry(let entry):
            EntryEditView(viewModel: viewModel, entry: entry)
        }
    }

    // MARK: - Date

    private var dateSwitcher: some View {
        HStack(spacing: 8) {
            Button { viewModel.shiftDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier("nutrition.date.prev")
            Spacer()
            Button { viewModel.goToToday() } label: {
                Text(dateTitle)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityHint("Goes to today")
            .accessibilityIdentifier("nutrition.date.label")
            Spacer()
            Button { viewModel.shiftDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next day")
            .accessibilityIdentifier("nutrition.date.next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
    }

    private var dateTitle: String {
        if viewModel.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(viewModel.date) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(viewModel.date) { return "Tomorrow" }
        return viewModel.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let daily = viewModel.daily
        let totals = daily?.totals ?? NutrientValues()
        let target = daily?.target
        return VStack(alignment: .leading, spacing: 14) {
            MacroRow(title: "Calories", id: "calories", unitName: "kilocalories", unitShort: "kcal",
                     consumed: totals.kcal, target: target?.kcal)
            MacroRow(title: "Protein", id: "protein", unitName: "grams", unitShort: "g",
                     consumed: totals.protein, target: target?.protein)
            MacroRow(title: "Carbs", id: "carbs", unitName: "grams", unitShort: "g",
                     consumed: totals.carbs, target: target?.carbs)
            MacroRow(title: "Fat", id: "fat", unitName: "grams", unitShort: "g",
                     consumed: totals.fat, target: target?.fat)
            if target == nil {
                Button { sheet = .targets } label: {
                    Label("Set daily targets", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition.target.set")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            actionButton("Quick add", icon: "plus.circle", id: "nutrition.quickAdd.button") { sheet = .quickAdd }
            actionButton("Scan label", icon: "text.viewfinder", id: "nutrition.scan.button") { sheet = .scan }
            actionButton("Add food", icon: "magnifyingglass", id: "nutrition.addFood.button") { sheet = .addFood }
        }
    }

    private func actionButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
            .padding(.vertical, 8)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Micros

    private var microsCard: some View {
        let micros = viewModel.daily?.totals.micros ?? Micronutrients()
        return DisclosureGroup(isExpanded: $microsExpanded) {
            VStack(spacing: 8) {
                ForEach(MicroKey.allCases, id: \.self) { key in
                    HStack {
                        Text(NutritionFormat.microLabel(key))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(micros[key].map { "\(NutritionFormat.amount($0)) \(key.unit)" } ?? "—")
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityLabel(micros[key].map { "\(NutritionFormat.amount($0)) \(key.unit)" } ?? "not recorded")
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("nutrition.micro.\(key.rawValue)")
                }
                ForEach(micros.other.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name.capitalized).foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(NutritionFormat.amount(micros.other[name] ?? 0)).foregroundStyle(AppTheme.textSecondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.top, 10)
        } label: {
            Text("Micronutrients")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .tint(AppTheme.accent)
        .lsCard()
    }

    // MARK: - Entries

    @ViewBuilder
    private var entriesSection: some View {
        let entries = viewModel.daily?.entries ?? []
        Text("Logged")
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
        if entries.isEmpty {
            Text("Nothing logged for this day yet.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .accessibilityIdentifier("nutrition.entries.empty")
        } else {
            ForEach(entries) { entry in
                Button { sheet = .editEntry(entry) } label: {
                    EntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition.entry.\(entry.id.uuidString)")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { viewModel.delete(entry) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("nutrition.entry.delete")
                }
            }
        }
    }
}

// MARK: - Macro row

private struct MacroRow: View {
    let title: String
    let id: String
    let unitName: String
    let unitShort: String
    let consumed: Double
    let target: Double?

    private var remaining: Double? { target.map { $0 - consumed } }

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(1, max(0, consumed / target))
    }

    private var remainingText: String {
        guard let remaining else { return "No target" }
        let magnitude = NutritionFormat.whole(abs(remaining))
        return remaining < 0 ? "\(magnitude) over" : "\(magnitude) left"
    }

    private var spoken: String {
        guard let target, let remaining else {
            return "\(title), \(NutritionFormat.whole(consumed)) \(unitName) logged, no target set"
        }
        let rem = NutritionFormat.whole(abs(remaining))
        let tail = remaining < 0 ? "\(rem) over target" : "\(rem) remaining"
        return "\(title), \(NutritionFormat.whole(consumed)) of \(NutritionFormat.whole(target)) \(unitName), \(tail)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(remainingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.surfaceElevated)
                    Capsule().fill(AppTheme.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
            Text(target.map { "\(NutritionFormat.whole(consumed)) / \(NutritionFormat.whole($0)) \(unitShort)" }
                 ?? "\(NutritionFormat.whole(consumed)) \(unitShort)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("nutrition.remaining.\(id)")
    }
}

// MARK: - Entry row

private struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        let total = entry.total
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                Text("\(NutritionFormat.amount(entry.servings)) × \(entry.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                Text("P \(NutritionFormat.whole(total.protein)) · C \(NutritionFormat.whole(total.carbs)) · F \(NutritionFormat.whole(total.fat))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Text("\(NutritionFormat.whole(total.kcal)) kcal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this entry")
    }
}
