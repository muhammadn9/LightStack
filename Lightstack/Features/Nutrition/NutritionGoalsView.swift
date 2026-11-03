import SwiftUI

private let weekdayInitials = ["S", "M", "T", "W", "T", "F", "S"]

private func weekdayName(_ weekday: Int) -> String {
    Calendar.current.weekdaySymbols[(weekday - 1) % 7]
}

private func weekdayShort(_ weekday: Int) -> String {
    Calendar.current.shortWeekdaySymbols[(weekday - 1) % 7]
}

/// Goals tab: one card per weekday macro plan, plus the setup entry points.
struct GoalsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let onStartSetup: () -> Void

    private enum EditorTarget: Identifiable {
        case new
        case plan(NutritionPlan)
        var id: String {
            switch self {
            case .new: return "new"
            case .plan(let plan): return plan.id.uuidString
            }
        }
    }

    @State private var editor: EditorTarget?

    var body: some View {
        VStack(spacing: 0) {
            NutritionScreenHeader(title: "My Goals", id: "goals.title")
            ScrollView {
                VStack(spacing: 14) {
                    if !viewModel.isSetupComplete { personalizeCard }
                    HStack {
                        Text("Plans").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Button { editor = .new } label: {
                            Image(systemName: "plus").font(.headline).foregroundStyle(AppTheme.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(AppTheme.surface, in: Circle())
                        }
                        .accessibilityLabel("Add plan")
                        .accessibilityIdentifier("goals.add")
                    }
                    if viewModel.plans.isEmpty {
                        emptyCard
                    } else {
                        ForEach(viewModel.plans) { plan in planCard(plan) }
                        uncoveredRow
                    }
                    if viewModel.isSetupComplete { recalculateButton }
                }
                .padding(16)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .sheet(item: $editor) { target in
            switch target {
            case .new: PlanEditorView(viewModel: viewModel, plan: nil)
            case .plan(let plan): PlanEditorView(viewModel: viewModel, plan: plan)
            }
        }
        .onAppear { viewModel.reload() }
    }

    private var personalizeCard: some View {
        Button(action: onStartSetup) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personalize your targets").font(.headline).foregroundStyle(AppTheme.textPrimary)
                    Text("Answer a few questions and we'll work out your calories and macros.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.6), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goals.personalize")
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Text("No targets yet").font(.headline).foregroundStyle(AppTheme.textPrimary)
            Text("Tap + to add a plan, or personalize your targets above.")
                .font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goals.empty")
    }

    private var recalculateButton: some View {
        Button(action: onStartSetup) {
            Label("Recalculate targets", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline).foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("goals.recalculate")
    }

    private func planCard(_ plan: NutritionPlan) -> some View {
        Button { editor = .plan(plan) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        Text("\(viewModel.slots.count) meals").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppTheme.textSecondary)
                }
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = plan.covers(weekday: day)
                        Text(weekdayInitials[day - 1])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? AppTheme.onAccent : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? AppTheme.accent : AppTheme.surfaceElevated,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Days: " + plan.weekdays.map(weekdayName).joined(separator: ", "))
                HStack(spacing: 8) {
                    tile("Protein", plan.protein, AppTheme.macroProtein, "goals.protein")
                    tile("Carbs", plan.carbs, AppTheme.macroCarbs, "goals.carbs")
                    tile("Fat", plan.fat, AppTheme.macroFat, "goals.fat")
                    tile("kcal", plan.kcal, AppTheme.macroKcal, "goals.calories")
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("goals.plan.\(plan.name)")
    }

    private func tile(_ title: String, _ value: Double, _ color: Color, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(NutritionFormat.whole(value)).font(.headline).foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var uncoveredRow: some View {
        let days = viewModel.uncoveredWeekdays()
        if !days.isEmpty {
            let base = viewModel.currentTarget() != nil
            Label {
                Text("\(days.map(weekdayShort).joined(separator: ", ")) not covered by any plan. "
                     + (base ? "Those days use your earlier base target." : "Those days have no target."))
                    .font(.footnote).foregroundStyle(AppTheme.textPrimary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppTheme.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("goals.uncovered")
        }
    }
}

// MARK: - Plan editor

/// Creates or edits a plan: name, weekdays, macros, calories (4/4/9 unless overridden).
/// In wizard mode (`wizardCalculation` set) it only edits the numbers and hands them back through `onWizardSave`.
struct PlanEditorView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let plan: NutritionPlan?
    var wizardCalculation: GoalCalculation?
    var onWizardSave: ((Double, Double, Double, Double?) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mask = 0
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var overrideKcal = false
    @State private var kcal = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var isWizard: Bool { wizardCalculation != nil }
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
    private var hasMacros: Bool {
        (proteinValue > 0 || carbsValue > 0 || fatValue > 0) || (overrideKcal && (typedKcal ?? 0) > 0)
    }
    private var canSave: Bool {
        hasMacros && (isWizard || (!name.trimmingCharacters(in: .whitespaces).isEmpty && mask & WeekdayMask.all != 0))
    }

    /// Weekdays currently owned by other plans, with that plan's name.
    private var otherOwners: [Int: String] {
        var result: [Int: String] = [:]
        for other in viewModel.allPlans() where other.id != plan?.id {
            for day in other.weekdays where result[day] == nil { result[day] = other.name }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isWizard {
                    Section {
                        TextField("Plan name", text: $name)
                            .frame(minHeight: 44)
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityIdentifier("plan.name")
                    } header: { Text("Name") }
                    .listRowBackground(AppTheme.surface)

                    Section {
                        daysRow
                        moveNote
                    } header: { Text("Days") }
                    footer: { Text("A day can only belong to one plan. Picking a day that another plan uses takes it from that plan.") }
                    .listRowBackground(AppTheme.surface)
                }

                Section {
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "nutrition.target.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "nutrition.target.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "nutrition.target.fat")
                } header: { Text("Macros per day") }
                .listRowBackground(AppTheme.surface)

                Section {
                    HStack {
                        Text("Calories from macros").foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(NutritionFormat.whole(derived)) kcal").foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("nutrition.target.derived")
                    }
                    Toggle("Set calories myself", isOn: $overrideKcal)
                        .tint(AppTheme.accent)
                        .accessibilityIdentifier("nutrition.target.override")
                    if overrideKcal {
                        NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "nutrition.target.kcal")
                        if let mismatch {
                            Label(mismatchText(mismatch), systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("nutrition.target.mismatch")
                        }
                    }
                } header: { Text("Calories") }
                footer: { Text("Calories are worked out as 4 per gram of protein and carbs and 9 per gram of fat unless you set your own.") }
                .listRowBackground(AppTheme.surface)

                if plan != nil {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("Delete plan").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("plan.delete")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .nutritionFormStyle()
            .navigationTitle(isWizard ? "Edit target" : (plan == nil ? "New plan" : "Edit plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWizard ? "Use this" : "Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("nutrition.target.save")
                }
            }
            .alert("Delete this plan?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let plan { viewModel.deletePlan(plan) }
                    dismiss()
                }
                .accessibilityIdentifier("plan.delete.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its days will use your earlier base target, if you have one.")
            }
            .onAppear(perform: load)
        }
    }

    private var daysRow: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = WeekdayMask.contains(mask, weekday: day)
                Button {
                    mask ^= WeekdayMask.bit(weekday: day)
                } label: {
                    Text(weekdayInitials[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? AppTheme.onAccent : AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? AppTheme.accent : AppTheme.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekdayName(day))
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("plan.day.\(day)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var moveNote: some View {
        let owners = otherOwners
        let moving = (1...7).filter { WeekdayMask.contains(mask, weekday: $0) && owners[$0] != nil }
        if !moving.isEmpty {
            Label(moving.map { "\(weekdayShort($0)) moves from \(owners[$0] ?? "")" }.joined(separator: ", "),
                  systemImage: "arrow.left.arrow.right")
                .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("plan.moveNote")
        }
    }

    private func mismatchText(_ diff: Double) -> String {
        let amount = NutritionFormat.whole(abs(diff))
        return diff > 0 ? "\(amount) kcal more than the macros add up to" : "\(amount) kcal fewer than the macros add up to"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let calc = wizardCalculation {
            protein = NutritionFormat.field(calc.proteinGrams)
            carbs = NutritionFormat.field(calc.carbsGrams)
            fat = NutritionFormat.field(calc.fatGrams)
            kcal = NutritionFormat.field(calc.kcal)
            return
        }
        if let plan {
            name = plan.name
            mask = plan.weekdayMask
            fill(from: plan)
            return
        }
        // New plan: first plan is "Daily" on every day; later ones start on the uncovered days and copy the first plan's numbers.
        let existing = viewModel.allPlans()
        if let first = existing.first {
            let uncovered = viewModel.uncoveredWeekdays()
            mask = WeekdayMask.mask(weekdays: uncovered)
            fill(from: first)
        } else {
            name = "Daily"
            mask = WeekdayMask.all
            if let base = viewModel.currentTarget() {
                protein = NutritionFormat.field(base.protein)
                carbs = NutritionFormat.field(base.carbs)
                fat = NutritionFormat.field(base.fat)
                overrideKcal = base.kcalOverridden
                kcal = NutritionFormat.field(base.kcal)
            }
        }
    }

    private func fill(from plan: NutritionPlan) {
        protein = NutritionFormat.field(plan.protein)
        carbs = NutritionFormat.field(plan.carbs)
        fat = NutritionFormat.field(plan.fat)
        overrideKcal = plan.kcalOverridden
        kcal = NutritionFormat.field(plan.kcal)
    }

    private func save() {
        let override = overrideKcal ? typedKcal : nil
        if isWizard {
            onWizardSave?(proteinValue, carbsValue, fatValue, override)
            dismiss()
            return
        }
        viewModel.savePlan(id: plan?.id, name: name, weekdayMask: mask, protein: proteinValue, carbs: carbsValue,
                           fat: fatValue, kcalOverride: override)
        dismiss()
    }
}
