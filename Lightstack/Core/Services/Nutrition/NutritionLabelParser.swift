import Foundation
import CoreGraphics

// MARK: - Public types

/// One recognised line of text. `box` is normalised (0-1) with the origin at the TOP-left;
/// `.zero` means "no geometry".
struct OCRLine: Equatable {
    let text: String
    let box: CGRect
    init(text: String, box: CGRect = .zero) {
        self.text = text
        self.box = box
    }
}

enum LabelFormat: String, Codable, Equatable {
    case us, euUK, unknown
}

enum LabelUnit: String, Codable, Equatable {
    case kcal, g, mg, mcg, iu
}

enum Nutrient: String, CaseIterable, Codable, Hashable {
    case calories, totalFat, saturatedFat, transFat, cholesterol, sodium
    case totalCarbs, fibre, sugars, addedSugars, protein
    case potassium, calcium, iron, vitaminD, vitaminA, vitaminC, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, vitaminB6, vitaminB12, folate, biotin, pantothenicAcid
    case magnesium, zinc, phosphorus, iodine, selenium, copper, manganese

    var displayName: String {
        switch self {
        case .calories: return "Calories"
        case .totalFat: return "Total fat"
        case .saturatedFat: return "Saturated fat"
        case .transFat: return "Trans fat"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .totalCarbs: return "Total carbohydrate"
        case .fibre: return "Fibre"
        case .sugars: return "Sugars"
        case .addedSugars: return "Added sugars"
        case .protein: return "Protein"
        case .vitaminD: return "Vitamin D"
        case .vitaminA: return "Vitamin A"
        case .vitaminC: return "Vitamin C"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        case .vitaminB6: return "Vitamin B6"
        case .vitaminB12: return "Vitamin B12"
        case .pantothenicAcid: return "Pantothenic acid"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Canonical storage unit.
    var canonicalUnit: LabelUnit {
        switch self {
        case .calories: return .kcal
        case .totalFat, .saturatedFat, .transFat, .totalCarbs, .fibre, .sugars, .addedSugars, .protein: return .g
        case .vitaminD, .vitaminA, .vitaminK, .vitaminB12, .folate, .biotin, .iodine, .selenium: return .mcg
        default: return .mg
        }
    }

    /// Standard daily value used only for the %DV cross-check (micros).
    var dailyValue: Double? {
        switch self {
        case .sodium: return 2300
        case .potassium: return 4700
        case .calcium: return 1300
        case .iron: return 18
        case .cholesterol: return 300
        default: return nil
        }
    }
}

struct ParsedValue: Equatable {
    var value: Double
    var unit: LabelUnit
    /// 0...1
    var confidence: Double
    /// The matched (normalised) line.
    var source: String
    /// The per-100 g / per-100 ml column value, when the label had one.
    var per100: Double?

    var needsReview: Bool { confidence < NutritionLabelParser.confidenceThreshold }
}

struct ParsedLabel: Equatable {
    var name: String?
    var servingLabel: String
    var servingGrams: Double?
    var servingMl: Double?
    var servingsPerContainer: Double?
    /// True when the serving was defaulted (per-100 g only label).
    var servingIsUncertain: Bool
    var format: LabelFormat
    var fields: [Nutrient: ParsedValue]
    var warnings: [String]

    var lowConfidenceFields: [Nutrient] {
        fields.filter { $0.value.needsReview }.map(\.key).sorted { $0.rawValue < $1.rawValue }
    }

    static let requiredNutrients: [Nutrient] = [.calories, .protein, .totalCarbs, .totalFat]
    var missingRequired: [Nutrient] { Self.requiredNutrients.filter { fields[$0] == nil } }
}

// MARK: - Parser

enum NutritionLabelParser {
    static let confidenceThreshold = 0.7

    static func parse(text: String) -> ParsedLabel {
        parse(lines: text.split(whereSeparator: \.isNewline).map { OCRLine(text: String($0)) })
    }

    static func parse(lines: [OCRLine]) -> ParsedLabel {
        let merged = mergeByBaseline(lines)
        var prepared = joinSplitLines(merged.map(normalize).filter { !$0.text.isEmpty })
        prepared.removeAll { $0.text.isEmpty }
        let fullText = prepared.map(\.text).joined(separator: "\n")

        let format = detectFormat(fullText)
        var warnings: [String] = []

        // Serving + columns
        var serving = parseServing(prepared)
        let colInfo = detectColumnInfo(prepared)
        let columns: [Column] = (format == .us || colInfo.columns.isEmpty) ? [.perServing] : colInfo.columns
        serving.columnGrams = colInfo.servingGrams
        serving.columnMl = colInfo.servingMl
        serving.per100IsMl = colInfo.per100IsMl

        // Nutrients
        var accs: [Nutrient: Acc] = [:]
        for line in prepared {
            extractNutrient(from: line, columns: columns, into: &accs, warnings: &warnings)
        }

        if accs.isEmpty {
            return ParsedLabel(name: nil, servingLabel: "", servingGrams: nil, servingMl: nil,
                               servingsPerContainer: serving.perContainer, servingIsUncertain: false,
                               format: .unknown, fields: [:],
                               warnings: ["No nutrition information found"] + warnings)
        }

        // Resolve to per-serving
        let hasServingCol = columns.contains(.perServing)
        var servingGrams = serving.grams
        var servingMl = serving.ml
        var servingLabel = serving.label
        var uncertain = false
        var factor = 1.0
        if hasServingCol {
            if let g = serving.columnGrams { servingGrams = g }
            if let m = serving.columnMl { servingMl = m }
            if servingLabel.isEmpty {
                if let g = servingGrams { servingLabel = formatQty(g) + " g" }
                else if let m = servingMl { servingLabel = formatQty(m) + " ml" }
                else if format != .us { servingLabel = "1 serving" }
            }
        } else {
            // per-100 only
            if let g = serving.grams ?? serving.ml {
                factor = g / 100
                if servingLabel.isEmpty { servingLabel = formatQty(g) + (serving.grams != nil ? " g" : " ml") }
            } else {
                uncertain = true
                if serving.per100IsMl { servingMl = 100; servingLabel = "100 ml" }
                else { servingGrams = 100; servingLabel = "100 g" }
                warnings.append("Only per-100 values found; serving set to 100 \(serving.per100IsMl ? "ml" : "g") - check it")
            }
        }

        var fields: [Nutrient: ParsedValue] = [:]
        for (nutrient, acc) in accs {
            var value: Double
            var conf = acc.confidence
            if hasServingCol {
                if let s = acc.serving { value = s }
                else if let p = acc.per100 {
                    if let g = servingGrams ?? servingMl { value = p * g / 100 } else { value = p; conf -= 0.3 }
                } else { continue }
            } else {
                guard let p = acc.per100 else { continue }
                value = p * factor
            }
            value = (value * 100).rounded() / 100
            fields[nutrient] = ParsedValue(value: value, unit: acc.unit, confidence: max(0, min(1, conf)),
                                           source: acc.source, per100: acc.per100)
            // %DV cross-check
            if let dv = acc.dv, let ref = nutrient.dailyValue, acc.unit == nutrient.canonicalUnit {
                let expected = value / ref * 100
                let lo = min(expected, dv), hi = max(expected, dv)
                if hi - lo > 10 && (lo == 0 || hi / lo > 1.5) {
                    fields[nutrient]?.confidence = max(0, min(1, conf) - 0.3)
                    warnings.append("\(nutrient.displayName) amount does not match its %DV - check it")
                }
            }
        }

        applyConsistencyChecks(&fields, warnings: &warnings)

        for n in ParsedLabel.requiredNutrients where fields[n] == nil {
            warnings.append("\(n.displayName) not found")
        }
        if servingLabel.isEmpty { warnings.append("Serving size not found") }

        return ParsedLabel(name: nil, servingLabel: servingLabel, servingGrams: servingGrams, servingMl: servingMl,
                           servingsPerContainer: serving.perContainer, servingIsUncertain: uncertain,
                           format: format, fields: fields, warnings: warnings)
    }

    // MARK: Consistency

    private static func applyConsistencyChecks(_ fields: inout [Nutrient: ParsedValue], warnings: inout [String]) {
        func cap(_ ns: [Nutrient]) {
            for n in ns {
                guard var v = fields[n] else { continue }
                v.confidence = min(v.confidence, 0.5)
                fields[n] = v
            }
        }
        if let kcal = fields[.calories]?.value, let p = fields[.protein]?.value,
           let c = fields[.totalCarbs]?.value, let f = fields[.totalFat]?.value {
            let computed = 4 * p + 4 * c + 9 * f
            let diff = abs(computed - kcal)
            if diff > 0.15 * max(kcal, 1) && diff > 10 {
                cap([.calories, .protein, .totalCarbs, .totalFat])
                warnings.append("Calories do not match the macros - check the values")
            }
        }
        if let s = fields[.sugars]?.value, let c = fields[.totalCarbs]?.value, s > c + 0.5 {
            cap([.sugars, .totalCarbs])
            warnings.append("Sugars are higher than total carbohydrate - check the values")
        }
        if let s = fields[.saturatedFat]?.value, let f = fields[.totalFat]?.value, s > f + 0.5 {
            cap([.saturatedFat, .totalFat])
            warnings.append("Saturated fat is higher than total fat - check the values")
        }
    }

    // MARK: Line preparation

    private struct Line {
        var text: String        // normalised, lowercase, %-tokens removed
        var original: String
        var dv: Double?
        var repaired: Bool
        var commaFixed: Bool
        var joined: Bool
    }

    private static func mergeByBaseline(_ lines: [OCRLine]) -> [String] {
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !usable.isEmpty else { return [] }
        guard usable.allSatisfy({ $0.box != .zero }) else {
            return usable.flatMap { $0.text.split(whereSeparator: \.isNewline).map(String.init) }
        }
        let avgH = usable.map { $0.box.height }.reduce(0, +) / Double(usable.count)
        let tol = max(avgH * 0.5, 0.005)
        let sorted = usable.sorted { $0.box.midY < $1.box.midY }
        var clusters: [[OCRLine]] = []
        for l in sorted {
            if let last = clusters.last, let ref = last.first, abs(ref.box.midY - l.box.midY) <= tol {
                clusters[clusters.count - 1].append(l)
            } else {
                clusters.append([l])
            }
        }
        return clusters.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    private static let unitTail = "(?:kcal|kj|mcg|µg|μg|ug|mg|iu|g)"

    private static func fixToken(_ tok: String) -> (String, Bool, Bool) {
        guard let g = RX.first(#"^([<(]?)([0-9OoIiLlSs.,]{1,7})(.*)$"#, in: tok) else { return (tok, false, false) }
        let lead = g[1] ?? "", core = g[2] ?? "", tail = g[3] ?? ""
        let hasDigit = core.contains { $0.isASCII && $0.isNumber }
        let tailLower = tail.lowercased()
        if hasDigit {
            guard RX.first("^(?:|%|[,;:)%].*|\(unitTail)(?![a-z]).*)$", in: tailLower) != nil else { return (tok, false, false) }
        } else {
            guard core.allSatisfy({ "OoLlIi".contains($0) }),
                  RX.first("^(?:\(unitTail)|%)$", in: tailLower) != nil else { return (tok, false, false) }
        }
        var repaired = false
        var out = ""
        for ch in core {
            switch ch {
            case "O", "o": out.append("0"); repaired = true
            case "l", "L", "I", "i": out.append("1"); repaired = true
            case "S", "s": out.append("5"); repaired = true
            default: out.append(ch)
            }
        }
        var commaFixed = false
        let commaCount = out.filter { $0 == "," }.count
        if commaCount == 1, let idx = out.firstIndex(of: ",") {
            let trailing = out.distance(from: idx, to: out.endIndex) - 1
            if trailing >= 1 && trailing <= 2 { out = out.replacingOccurrences(of: ",", with: "."); commaFixed = true }
            else { out = out.replacingOccurrences(of: ",", with: "") }
        } else if commaCount > 1 {
            out = out.replacingOccurrences(of: ",", with: "")
        }
        return (lead + out + tail, repaired, commaFixed)
    }

    private static func normalize(_ raw: String) -> Line {
        let original = raw.trimmingCharacters(in: .whitespaces)
        var s = original.replacingOccurrences(of: "/", with: " / ")
        s = s.replacingOccurrences(of: "less than", with: "<", options: .caseInsensitive)
        var repaired = false, commaFixed = false
        let fixed = s.split(whereSeparator: \.isWhitespace).map { tok -> String in
            let (t, r, c) = fixToken(String(tok))
            repaired = repaired || r
            commaFixed = commaFixed || c
            return t
        }.joined(separator: " ")
        var text = fixed.lowercased()
        // %DV: remember the last one, then strip
        var dv: Double?
        for m in RX.matches(#"<?\s*(\d+(?:\.\d+)?)\s*%"#, in: text) { dv = m.groups[1].flatMap(Double.init) }
        text = RX.replace(#"<?\s*\d+(?:\.\d+)?\s*%"#, in: text, with: " ")
        text = RX.replace(#"%\s*(?:dv|rdv|ri|daily value)"#, in: text, with: " ")
        text = text.replacingOccurrences(of: "%", with: " ")
        text = RX.replace(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespaces)
        return Line(text: text, original: original, dv: dv, repaired: repaired, commaFixed: commaFixed, joined: false)
    }

    /// Joins "Protein" + "3g" style splits where the value landed on the next line.
    private static func joinSplitLines(_ lines: [Line]) -> [Line] {
        var out: [Line] = []
        var i = 0
        while i < lines.count {
            var l = lines[i]
            let hasDigit = l.text.contains { $0.isNumber }
            if !hasDigit, l.dv == nil, i + 1 < lines.count,
               lookup(l.text) != nil || RX.first(servingSizePattern, in: l.text) != nil,
               let first = lines[i + 1].text.first, first.isNumber || first == "<" || first == "(" {
                let n = lines[i + 1]
                l.text += " " + n.text
                l.original += " " + n.original
                l.dv = n.dv
                l.repaired = l.repaired || n.repaired
                l.commaFixed = l.commaFixed || n.commaFixed
                l.joined = true
                i += 1
            }
            out.append(l)
            i += 1
        }
        return out
    }

    // MARK: Format / serving / columns

    private static func detectFormat(_ text: String) -> LabelFormat {
        var us = 0, eu = 0
        for k in ["nutrition facts", "serving size", "daily value", "%dv", "amount per serving", "servings per container"] where text.contains(k) { us += 1 }
        for k in ["nutrition information", "nutritional information", "per 100", "kj", "typical values", "of which", "reference intake"] where text.contains(k) { eu += 1 }
        if text.contains("per serving") && !text.contains("amount per serving") { eu += 1 }
        if us == 0 && eu == 0 { return .unknown }
        return us > eu ? .us : (eu > us ? .euUK : (text.contains("kj") ? .euUK : .us))
    }

    private enum Column { case per100, perServing }

    private static let servingSizePattern = #"serv(?:ing|\.)?\s*size|portion size"#

    private struct ServingInfo {
        var label = ""
        var grams: Double?
        var ml: Double?
        var perContainer: Double?
        var columnGrams: Double?
        var columnMl: Double?
        var per100IsMl = false
    }

    private static func parseServing(_ lines: [Line]) -> ServingInfo {
        var info = ServingInfo()
        for line in lines {
            let t = line.text
            if info.perContainer == nil {
                if let g = RX.first(#"(\d+(?:\.\d+)?)\s*servings?\s*per\s*(?:container|pack|package|tub|bottle|can)"#, in: t),
                   let v = g[1].flatMap(Double.init) { info.perContainer = v }
                else if let g = RX.first(#"servings?\s*per\s*(?:container|pack|package|tub|bottle|can)[^0-9]{0,12}(\d+(?:\.\d+)?)"#, in: t),
                        let v = g[1].flatMap(Double.init) { info.perContainer = v }
                else if let g = RX.first(#"(?:contains|makes)\s*(?:about\s*)?(\d+(?:\.\d+)?)\s*servings?"#, in: t),
                        let v = g[1].flatMap(Double.init) { info.perContainer = v }
            }
            if info.label.isEmpty, RX.first(servingSizePattern, in: t) != nil {
                var label = line.original
                if let r = label.range(of: servingSizePattern, options: [.regularExpression, .caseInsensitive]) {
                    label = String(label[r.upperBound...])
                }
                if let r = label.range(of: "servings? per", options: [.regularExpression, .caseInsensitive]) {
                    label = String(label[..<r.lowerBound])
                }
                label = label.trimmingCharacters(in: CharacterSet(charactersIn: ":- ").union(.whitespaces))
                if let after = t.range(of: servingSizePattern, options: .regularExpression) {
                    let rest = String(t[after.upperBound...])
                    if let g = RX.first(#"\(\s*(\d+(?:\.\d+)?)\s*(g|ml)\s*\)"#, in: rest) ?? RX.first(#"(?<![\d.])(\d+(?:\.\d+)?)\s*(g|ml)(?![a-z])"#, in: rest),
                       let v = g[1].flatMap(Double.init) {
                        if g[2] == "ml" { info.ml = v } else { info.grams = v }
                    } else if let g = RX.first(#"(\d+(?:\.\d+)?)\s*(?:oz|ounces?)(?![a-z])"#, in: rest), let v = g[1].flatMap(Double.init) {
                        info.grams = NutritionUnit.oz.grams(forQuantity: v)
                    }
                }
                info.label = label
            }
        }
        return info
    }

    private struct ColumnInfo { var columns: [Column] = []; var servingGrams: Double?; var servingMl: Double?; var per100IsMl = false }

    private static func detectColumnInfo(_ lines: [Line]) -> ColumnInfo {
        var info = ColumnInfo()
        var found: [(Int, Column)] = []
        for line in lines {
            let t = line.text
            var local: [(Int, Column, Double?, String?)] = []
            for m in RX.matches(#"per\s*100\s*(g|ml)"#, in: t) { local.append((m.loc, .per100, nil, m.groups[1])) }
            for m in RX.matches(#"per\s*(\d+(?:\.\d+)?)\s*(g|ml)\s*(?:serving|portion)"#, in: t) {
                local.append((m.loc, .perServing, m.groups[1].flatMap(Double.init), m.groups[2]))
            }
            for m in RX.matches(#"(?<!amount )per\s*(?:serving|portion)(?:\s*\(?\s*(\d+(?:\.\d+)?)\s*(g|ml)\s*\)?)?"#, in: t) {
                local.append((m.loc, .perServing, m.groups[1].flatMap(Double.init), m.groups[2]))
            }
            for (loc, col, v, unit) in local.sorted(by: { $0.0 < $1.0 }) {
                if col == .per100 {
                    if !found.contains(where: { $0.1 == .per100 }) { found.append((loc, .per100)); info.per100IsMl = unit == "ml" }
                } else {
                    if !found.contains(where: { $0.1 == .perServing }) { found.append((loc, .perServing)) }
                    if let v = v, info.servingGrams == nil, info.servingMl == nil {
                        if unit == "ml" { info.servingMl = v } else { info.servingGrams = v }
                    }
                }
            }
        }
        info.columns = found.map(\.1)
        return info
    }

    private static func formatQty(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: Nutrient extraction

    private struct Acc {
        var per100: Double?
        var serving: Double?
        var unit: LabelUnit
        var confidence: Double
        var source: String
        var dv: Double?
        var salt = false
    }

    private struct Amount { var value: Double; var unit: LabelUnit?; var lessThan: Bool }

    private enum Entry { case nutrient(Nutrient), salt, ignore }

    private static let synonyms: [(String, Entry)] = {
        var t: [(String, Entry)] = []
        func add(_ n: Nutrient, _ names: [String]) { names.forEach { t.append(($0, .nutrient(n))) } }
        add(.calories, ["calories", "calorie", "energy"])
        add(.totalFat, ["total fat", "fat", "fats"])
        add(.saturatedFat, ["saturated fat", "saturated fatty acids", "saturates", "of which saturates", "of which saturated", "saturated", "sat fat", "sat. fat"])
        add(.transFat, ["trans fat", "trans fatty acids", "trans"])
        add(.cholesterol, ["cholesterol"])
        add(.sodium, ["sodium"])
        add(.totalCarbs, ["total carbohydrate", "total carbohydrates", "carbohydrate", "carbohydrates", "total carbs", "carbs"])
        add(.fibre, ["dietary fiber", "dietary fibre", "fiber", "fibre"])
        add(.sugars, ["total sugars", "total sugar", "of which sugars", "sugars", "sugar"])
        add(.addedSugars, ["added sugars", "added sugar"])
        add(.protein, ["protein", "proteins"])
        add(.potassium, ["potassium"])
        add(.calcium, ["calcium"])
        add(.iron, ["iron"])
        add(.vitaminD, ["vitamin d", "vitamin d3", "vitamin d2"])
        add(.vitaminA, ["vitamin a"])
        add(.vitaminC, ["vitamin c"])
        add(.vitaminE, ["vitamin e"])
        add(.vitaminK, ["vitamin k"])
        add(.thiamin, ["thiamin", "thiamine", "vitamin b1"])
        add(.riboflavin, ["riboflavin", "vitamin b2"])
        add(.niacin, ["niacin", "vitamin b3"])
        add(.vitaminB6, ["vitamin b6"])
        add(.vitaminB12, ["vitamin b12"])
        add(.folate, ["folate", "folic acid"])
        add(.biotin, ["biotin"])
        add(.pantothenicAcid, ["pantothenic acid"])
        add(.magnesium, ["magnesium"])
        add(.zinc, ["zinc"])
        add(.phosphorus, ["phosphorus"])
        add(.iodine, ["iodine"])
        add(.selenium, ["selenium"])
        add(.copper, ["copper"])
        add(.manganese, ["manganese"])
        t.append(("salt", .salt))
        for p in ["calories from fat", "calories from saturated fat", "energy from fat"] { t.append((p, .ignore)) }
        return t.sorted { $0.0.count > $1.0.count }
    }()

    private static let ignoredPhrases = ["a day", "general nutrition advice", "calorie diet", "reference intake", "based on a", "daily diet"]

    private static func findWord(_ word: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let r = text.range(of: word, range: searchStart..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return r }
            searchStart = r.upperBound
        }
        return nil
    }

    private static func lookup(_ text: String) -> (Entry, Range<String.Index>)? {
        if ignoredPhrases.contains(where: { text.contains($0) }) { return nil }
        for (word, entry) in synonyms {
            if let r = findWord(word, in: text) { return (entry, r) }
        }
        return nil
    }

    private static func amounts(in s: String) -> [Amount] {
        RX.matches(#"(?<![0-9.])(<)?\s*(\d+(?:\.\d+)?)\s*(kcal|kj|mcg|µg|μg|ug|mg|iu|g)?(?![a-z0-9])"#, in: s).compactMap { m in
            guard let v = m.groups[2].flatMap(Double.init) else { return nil }
            let unit: LabelUnit?
            switch m.groups[3] {
            case "kcal": unit = .kcal
            case "kj": unit = .kcal // energy marker; filtered out for non-energy nutrients
            case "mcg", "µg", "μg", "ug": unit = .mcg
            case "mg": unit = .mg
            case "iu": unit = .iu
            case "g": unit = .g
            default: unit = nil
            }
            return Amount(value: v, unit: unit, lessThan: m.groups[1] != nil)
        }
    }

    /// Amounts with kJ distinguished (energy only).
    private static func energyAmounts(in s: String) -> (kcal: [Double], kj: [Double], plain: [Double]) {
        var kcal: [Double] = [], kj: [Double] = [], plain: [Double] = []
        for m in RX.matches(#"(?<![0-9.])(\d+(?:\.\d+)?)\s*(kcal|kj)?(?![a-z0-9])"#, in: s) {
            guard let v = m.groups[1].flatMap(Double.init) else { continue }
            switch m.groups[2] {
            case "kcal": kcal.append(v)
            case "kj": kj.append(v)
            default: plain.append(v)
            }
        }
        return (kcal, kj, plain)
    }

    private static let massFactor: [LabelUnit: Double] = [.g: 1, .mg: 0.001, .mcg: 0.000001]

    private static func convert(_ a: Amount, to canon: LabelUnit) -> (Double, LabelUnit, Bool)? {
        let base = a.lessThan ? a.value / 2 : a.value
        guard let u = a.unit else { return (base, canon, true) }
        if u == canon { return (base, canon, false) }
        if u == .iu { return (base, .iu, false) }
        if let from = massFactor[u], let to = massFactor[canon] { return (base * from / to, canon, false) }
        return nil
    }

    private static func extractNutrient(from line: Line, columns: [Column], into accs: inout [Nutrient: Acc], warnings: inout [String]) {
        guard let (entry, range) = lookup(line.text) else { return }
        let text = line.text
        let after = String(text[range.upperBound...])
        let before = String(text[..<range.lowerBound])

        let nutrient: Nutrient
        var isSalt = false
        switch entry {
        case .ignore: return
        case .nutrient(let n): nutrient = n
        case .salt: nutrient = .sodium; isSalt = true
        }
        if let existing = accs[nutrient] {
            // sodium beats salt; otherwise first hit wins
            if !(existing.salt && !isSalt) { return }
        }

        var base = 0.95
        if line.repaired { base -= 0.3 }
        if line.commaFixed { base -= 0.1 }
        if line.joined { base -= 0.1 }

        var values: [Double?] = []   // per column, canonical units
        var unit = nutrient.canonicalUnit
        var capLow = false

        if nutrient == .calories {
            var e = energyAmounts(in: after)
            if e.kcal.isEmpty && e.kj.isEmpty && e.plain.isEmpty { e = energyAmounts(in: before) }
            var kcal = e.kcal
            let kj = e.kj
            if kcal.isEmpty && kj.isEmpty && !e.plain.isEmpty {
                kcal = e.plain
                if !findWordIsCalories(text, range) { base -= 0.3 }
            }
            guard !(kcal.isEmpty && kj.isEmpty) else { noAmount(line, nutrient, &warnings); return }
            var derived = false
            for i in 0..<columns.count {
                if i < kcal.count { values.append(kcal[i]) }
                else if i < kj.count { values.append((kj[i] / 4.184 * 10).rounded() / 10); derived = true }
                else { values.append(nil) }
            }
            if derived { base -= 0.15 }
            unit = .kcal
        } else {
            var amts = amounts(in: after).filter { $0.unit != .kcal }
            if amts.isEmpty { amts = amounts(in: before).filter { $0.unit != .kcal } }
            // drop kJ-looking leftovers (unit nil because kj mapped to nil)
            if amts.isEmpty {
                let zeroWord = RX.first(#"\b(?:trace|nil|tr)\b|^\s*[-–—]+\s*$"#, in: after) != nil
                if zeroWord { amts = [Amount(value: 0, unit: isSalt ? .g : nutrient.canonicalUnit, lessThan: false)]; base -= 0.1 }
                else { noAmount(line, nutrient, &warnings); return }
            }
            let target = isSalt ? LabelUnit.g : nutrient.canonicalUnit
            var guessed = false
            for i in 0..<columns.count {
                guard i < amts.count, let c = convert(amts[i], to: target) else { values.append(nil); continue }
                var v = c.0
                if amts[i].lessThan { capLow = true }
                if c.2 { guessed = true }
                if isSalt { v = v * 400; unit = .mg } else { unit = c.1 }
                values.append(v)
            }
            if guessed { base -= 0.3 }
            if capLow { base = min(base, 0.5) }
        }

        var acc = Acc(per100: nil, serving: nil, unit: unit, confidence: base, source: text, dv: line.dv, salt: isSalt)
        for (i, col) in columns.enumerated() where i < values.count {
            guard let v = values[i] else { continue }
            if col == .per100 { acc.per100 = v } else { acc.serving = v }
        }
        // single amount on a dual-column line: treat it as the first column only
        guard acc.per100 != nil || acc.serving != nil else { return }
        accs[nutrient] = acc
    }

    private static func findWordIsCalories(_ text: String, _ r: Range<String.Index>) -> Bool {
        text[r].hasPrefix("calor")
    }

    private static func noAmount(_ line: Line, _ nutrient: Nutrient, _ warnings: inout [String]) {
        if line.dv != nil {
            warnings.append("\(nutrient.displayName): only %DV shown, amount not stored")
        }
    }
}

// MARK: - Regex helper

private enum RX {
    struct Match { let loc: Int; let groups: [String?] }

    static func matches(_ pattern: String, in s: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            Match(loc: m.range.location, groups: (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            })
        }
    }

    static func first(_ pattern: String, in s: String) -> [String?]? {
        matches(pattern, in: s).first?.groups
    }

    static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
