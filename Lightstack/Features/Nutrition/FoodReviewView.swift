import SwiftUI

/// Maps parsed label nutrients onto the stored micronutrient keys.
extension Nutrient {
    var microKey: MicroKey? {
        switch self {
        case .fibre: return .fiber
        case .sugars: return .sugar
        case .addedSugars: return .addedSugar
        case .saturatedFat: return .satFat
        case .transFat: return .transFat
        case .cholesterol: return .cholesterol
        case .sodium: return .sodium
        case .potassium: return .potassium
        case .calcium: return .calcium
        case .iron: return .iron
        case .vitaminD: return .vitaminD
        default: return nil
        }
    }

    var isMainMacro: Bool {
        switch self {
        case .calories, .protein, .totalCarbs, .totalFat: return true
        default: return false
        }
    }
}

/// Best-effort split of a household serving text ("2/3 cup (55g)") into an amount and a unit.
enum ServingGuess {
    static func make(from label: ParsedLabel) -> (amount: Double, unit: NutritionUnit) {
        if label.servingIsUncertain {
            if let g = label.servingGrams { return (g, .g) }
            if let ml = label.servingMl { return (ml, .ml) }
            return (100, .g)
        }
        let head = label.servingLabel.lowercased().components(separatedBy: "(").first ?? ""
        var tokens = head.split(whereSeparator: \.isWhitespace).map(String.init)
        var amount = 0.0
        var consumed = false
        while let first = tokens.first, let value = number(first) {
            amount += value
            consumed = true
            tokens.removeFirst()
        }
        if consumed, amount > 0 {
            let rest = tokens.joined(separator: " ")
            if let unit = NutritionUnit.parse(rest) { return (amount, unit) }
            if let word = tokens.first, let unit = NutritionUnit.parse(word) { return (amount, unit) }
            if let g = label.servingGrams, rest.isEmpty { return (g, .g) }
            return (amount, .serving)
        }
        if let g = label.servingGrams { return (g, .g) }
        if let ml = label.servingMl { return (ml, .ml) }
        return (1, .serving)
    }

    private static func number(_ token: String) -> Double? {
        if let slash = token.firstIndex(of: "/") {
            let n = Double(token[token.startIndex..<slash])
            let d = Double(token[token.index(after: slash)...])
            if let n, let d, d != 0 { return n / d }
            return nil
        }
        return Double(token.replacingOccurrences(of: ",", with: "."))
    }
}

/// Review form for a scanned (or hand-entered) food. Everything is editable; nothing is saved until Save.
struct FoodReviewView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var mealSlotId: UUID?
    /// Whether "Log it now" starts switched on (off when only saving to the Kitchen).
    var logByDefault = true
    let parsed: ParsedLabel
    let onSaved: () -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var servingLabel = ""
    @State private var servingAmount = ""
    @State private var servingUnit: NutritionUnit = .serving
    @State private var servingGrams = ""
    @State private var texts: [Nutrient: String] = [:]
    @State private var initial: [Nutrient: String] = [:]
    @State private var showMicros = false
    @State private var logNow = true
    @State private var servingsToLog = "1"
    @State private var loaded = false

    private static let macroOrder: [Nutrient] = [.calories, .protein, .totalCarbs, .totalFat]

    private var microNutrients: [Nutrient] {
        let stored = Nutrient.allCases.filter { $0.microKey != nil }
        let extras = Nutrient.allCases.filter { $0.microKey == nil && !$0.isMainMacro && parsed.fields[$0] != nil }
        return stored + extras
    }

    private func flagged(_ n: Nutrient) -> Bool {
        let text = texts[n] ?? ""
        if Self.macroOrder.contains(n), text.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let field = parsed.fields[n], field.needsReview else { return false }
        return text == initial[n]
    }

    private var servingFlagged: Bool {
        guard parsed.servingIsUncertain || parsed.servingLabel.isEmpty else { return false }
        return servingAmount == NutritionFormat.field(ServingGuess.make(from: parsed).amount)
            && servingUnit == ServingGuess.make(from: parsed).unit
    }

    private var anyMicroFlagged: Bool { microNutrients.contains(where: flagged) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && NutritionFormat.parse(texts[.calories] ?? "") != nil
            && (NutritionFormat.parse(servingAmount) ?? 0) > 0
    }

    var body: some View {
        Form {
            if !parsed.warnings.isEmpty || !parsed.missingRequired.isEmpty {
                Section {
                    ForEach(parsed.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    if !parsed.missingRequired.isEmpty {
                        Label("Some values were not read. Fill in the highlighted fields.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                } header: {
                    Text("Check the scan")
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                TextField("Food name", text: $name)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("nutrition.review.name")
                TextField("Brand (optional)", text: $brand)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("nutrition.review.brand")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                TextField("Serving description", text: $servingLabel)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("nutrition.review.servingLabel")
                NutritionField(title: "Serving size", unit: "", text: $servingAmount,
                               id: "nutrition.review.servingAmount", flagged: servingFlagged,
                               flagID: "nutrition.review.flag.serving", placeholder: "1")
                Picker("Serving unit", selection: $servingUnit) {
                    ForEach(NutritionUnit.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("nutrition.review.servingUnit")
                NutritionField(title: "Weight of one serving", unit: "g", text: $servingGrams,
                               id: "nutrition.review.servingGrams", placeholder: "optional")
                if parsed.servingIsUncertain {
                    Label("No serving size on the label, so values are per 100 g. Change the serving if you need to.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } header: {
                Text("Serving")
            } footer: {
                Text("Values below are per one serving.")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                ForEach(Self.macroOrder, id: \.self) { n in nutrientField(n) }
            } header: {
                Text("Nutrition per serving")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                DisclosureGroup("Micronutrients", isExpanded: $showMicros) {
                    ForEach(microNutrients, id: \.self) { n in nutrientField(n, placeholder: "—") }
                }
                .tint(AppTheme.accent)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                Toggle("Log it now", isOn: $logNow)
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("nutrition.review.logToggle")
                if logNow {
                    NutritionField(title: "Servings", unit: "", text: $servingsToLog,
                                   id: "nutrition.review.servings", placeholder: "1")
                }
            } header: {
                Text("Log")
            }
            .listRowBackground(AppTheme.surface)
        }
        .nutritionFormStyle()
        .navigationTitle("Review food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
                    .accessibilityIdentifier("nutrition.review.save")
            }
        }
        .onAppear(perform: load)
    }

    private func nutrientField(_ n: Nutrient, placeholder: String = "0") -> some View {
        NutritionField(
            title: n.displayName, unit: n.canonicalUnit.rawValue,
            text: Binding(get: { texts[n] ?? "" }, set: { texts[n] = $0 }),
            id: "nutrition.review.field.\(n.rawValue)", flagged: flagged(n),
            flagID: "nutrition.review.flag.\(n.rawValue)", placeholder: placeholder
        )
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        logNow = logByDefault
        name = parsed.name ?? ""
        let guess = ServingGuess.make(from: parsed)
        servingLabel = parsed.servingLabel.isEmpty || parsed.servingIsUncertain
            ? "\(NutritionFormat.amount(guess.amount)) \(guess.unit.displayName)" : parsed.servingLabel
        servingAmount = NutritionFormat.field(guess.amount)
        servingUnit = guess.unit
        servingGrams = NutritionFormat.field(parsed.servingGrams)
        var values: [Nutrient: String] = [:]
        for n in Nutrient.allCases {
            if let field = parsed.fields[n] { values[n] = NutritionFormat.field(field.value) }
        }
        texts = values
        initial = values
        showMicros = anyMicroFlagged
    }

    private func save() {
        guard let userId = viewModel.userId, canSave else { return }
        func value(_ n: Nutrient) -> Double? { NutritionFormat.parse(texts[n] ?? "").map { max(0, $0) } }
        var micros = Micronutrients()
        for n in microNutrients {
            guard let v = value(n) else { continue }
            if let key = n.microKey { micros[key] = v } else { micros.other[n.displayName] = v }
        }
        let nutrients = NutrientValues(kcal: value(.calories) ?? 0, protein: value(.protein) ?? 0,
                                       carbs: value(.totalCarbs) ?? 0, fat: value(.totalFat) ?? 0, micros: micros)
        let amount = NutritionFormat.parse(servingAmount) ?? 1
        let trimmedLabel = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedLabel.isEmpty ? "\(NutritionFormat.amount(amount)) \(servingUnit.displayName)" : trimmedLabel
        let grams = NutritionFormat.parse(servingGrams).flatMap { $0 > 0 ? $0 : nil } ?? servingUnit.grams(forQuantity: amount)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = NutritionFood.make(userId: userId, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                      brand: trimmedBrand.isEmpty ? nil : trimmedBrand, servingLabel: label,
                                      servingUnit: servingUnit.rawValue, servingAmount: amount, servingGrams: grams,
                                      nutrients: nutrients, source: .scan)
        let toLog = logNow ? (NutritionFormat.parse(servingsToLog) ?? 1) : nil
        viewModel.saveFood(food, logServings: toLog, mealSlotId: mealSlotId)
        onSaved()
    }
}
