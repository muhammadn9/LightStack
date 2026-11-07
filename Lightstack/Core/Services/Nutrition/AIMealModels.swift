import Foundation

// MARK: - Models

/// Where the user is logging (a hint for the model: "dinner" vs "snack").
struct AIMealContext: Equatable {
    var mealName: String?
    init(mealName: String? = nil) { self.mealName = mealName }
}

/// One item the AI found in a description or photo. `fullItem` is the nutrition of the WHOLE item (a full
/// burrito bowl); what the user ate is `servings` times that, so "half" is 0.5. The user may edit any field
/// before logging.
struct AIMealItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var restaurant: String?
    var brand: String?
    /// What the user said they ate, e.g. "half".
    var portionText: String
    /// Multiplier of the full item that was eaten (0.5 = half).
    var servings: Double
    /// e.g. "1 bowl" or "1 cup (245 g)".
    var servingLabel: String
    /// Nutrition of one full item (macros plus fiber, sugar, sodium, saturated fat when known).
    var fullItem: NutrientValues
    var confidence: AIConfidence
    var notes: String
    /// Web pages the estimate was grounded on (from the search call; empty without a restaurant lookup).
    var sources: [AIFoodSource] = []

    /// What was actually eaten: the full item scaled by `servings`.
    var eaten: NutrientValues { fullItem.scaled(by: servings) }

    /// The place shown under the name: restaurant first, then brand.
    var venue: String? { restaurant ?? brand }

    /// True when the calories disagree a lot with 4/4/9 from the macros (the model's numbers are inconsistent).
    var kcalLooksOff: Bool {
        let derived = NutritionMath.derivedKcal(protein: fullItem.protein, carbs: fullItem.carbs, fat: fullItem.fat)
        let diff = abs(fullItem.kcal - derived)
        return diff > 75 && diff > 0.25 * max(fullItem.kcal, derived)
    }
}

/// What one estimate call returns.
struct AIMealEstimate: Equatable {
    var items: [AIMealItem]
    /// Set when the model could not estimate without more information. Items may be empty then.
    var clarifyingQuestion: String?
    /// True when the Google Search tool was on for this call.
    var usedSearch: Bool
    /// Every grounding source of the call.
    var sources: [AIFoodSource]
}

// MARK: - Errors

/// Failures the UI can show as-is (`message`).
enum NutritionAIError: Error, Equatable, LocalizedError {
    /// The ai-proxy per-user limit; carries the proxy's own message.
    case rateLimited(String)
    case offline
    case timeout
    /// The reply was not the JSON we asked for.
    case unparseable
    /// Nothing to estimate (blank input) or the model found no food.
    case empty
    /// Anything else (signed out, service down, ...), with a readable message.
    case failed(String)

    var message: String {
        switch self {
        case .rateLimited(let message): return message
        case .offline: return "You're offline. Connect to the internet to estimate a meal with AI."
        case .timeout: return "The AI took too long to respond. Please try again."
        case .unparseable: return "I couldn't read the AI's answer. Please try again, or describe the meal a bit differently."
        case .empty: return "I couldn't find any food in that. Describe what you ate, or add a photo."
        case .failed(let message): return message
        }
    }

    var errorDescription: String? { message }

    /// Maps a provider or network error to a typed one.
    static func from(_ error: Error) -> NutritionAIError {
        if let typed = error as? NutritionAIError { return typed }
        let ns = error as NSError
        if ns.domain == GeminiService.proxyErrorDomain {
            switch ns.code {
            case 429: return .rateLimited(ns.localizedDescription)
            case 504: return .timeout
            default: return .failed(ns.localizedDescription)
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .timedOut: return .timeout
            default: break
            }
        }
        if let provider = error as? AIProviderError, case .allProvidersUnavailable = provider {
            return .failed("The AI is busy right now. Please try again in a minute.")
        }
        let text = ns.localizedDescription
        if text.lowercased().contains("failed to parse") { return .unparseable }
        return .failed("The AI couldn't be reached. Please try again.")
    }
}

// MARK: - Restaurant detection

/// Decides whether a description mentions a restaurant, so only those calls pay for Google Search.
///
/// Search is ON when the text has any of:
/// 1. a well-known chain name (case-insensitive: "chipotle", "mcdonald", "starbucks", ...);
/// 2. a restaurant word: restaurant, diner, cafe, bistro, pizzeria, steakhouse, takeout/take-out/takeaway,
///    drive-thru, food truck, "menu";
/// 3. "from" or "at" followed by a capitalised name ("from Sweetgreen", "at Joe's"), unless it is a
///    capitalised meal or place word ("at Home", "from Costco" is still a hit);
/// 4. a capitalised possessive name ("Wendy's", "Joe's Pizza"), except family words ("Mom's").
/// Everything else (a plain description or a photo alone) skips search to keep calls cheap.
enum RestaurantSignal {
    static let knownChains: [String] = [
        "chipotle", "mcdonald", "burger king", "wendy's", "wendys", "subway", "starbucks", "taco bell", "chick-fil-a",
        "chick fil a", "chickfila", "kfc", "popeyes", "panera", "domino", "pizza hut", "papa john", "dunkin", "five guys",
        "shake shack", "in-n-out", "in n out", "panda express", "sweetgreen", "cava", "wingstop", "jersey mike",
        "jimmy john", "arby", "sonic drive", "chili's", "olive garden", "applebee", "ihop", "denny's", "cheesecake factory",
        "texas roadhouse", "outback", "red lobster", "nando", "greggs", "pret a manger", "wagamama", "tim hortons",
        "little caesars", "culver", "whataburger", "jack in the box", "zaxby", "raising cane", "qdoba", "moe's southwest",
        "noodles & company", "noodles and company", "firehouse subs", "potbelly", "tropical smoothie", "jamba",
        "baskin", "dairy queen", "krispy kreme", "auntie anne", "cinnabon", "el pollo loco", "del taco", "carl's jr",
        "hardee", "white castle", "buffalo wild wings", "cracker barrel", "waffle house", "bojangles", "habit burger",
        "freebirds", "pei wei", "p.f. chang", "pf chang", "buca di beppo", "carrabba", "bonefish", "longhorn", "chuy's",
        "hooters", "tgi friday", "ruby tuesday", "bob evans", "golden corral", "benihana", "joe & the juice",
        "yo! sushi", "mod pizza", "blaze pizza", "marco's pizza"
    ]

    /// Short names that must match as whole words ("cava" is not "cavatappi").
    private static let wholeWord: Set<String> = ["kfc", "cava", "subway", "outback", "ihop", "jamba", "baskin", "arby", "sonic drive"]

    static let keywords: [String] = [
        "restaurant", "diner", "cafe", "café", "bistro", "pizzeria", "steakhouse", "takeout", "take-out", "takeaway",
        "take away", "drive-thru", "drive thru", "drive-through", "food truck", "the menu", "off the menu", "from the menu"
    ]

    /// Capitalised words after "from/at" that are not places.
    private static let notPlaces: Set<String> = [
        "Home", "Work", "Lunch", "Dinner", "Breakfast", "Brunch", "Night", "Noon", "Midnight", "Morning", "Evening",
        "The", "A", "An", "My", "I", "Mom", "Dad", "Grandma", "Grandpa", "Least", "Most", "Once", "First", "Last"
    ]
    private static let family: Set<String> = ["Mom's", "Dad's", "Grandma's", "Grandpa's", "Mum's", "Nana's", "Gran's", "Today's", "Yesterday's"]

    static func mentionsRestaurant(_ text: String) -> Bool {
        let lower = text.lowercased()
        for chain in knownChains where lower.contains(chain) {
            guard wholeWord.contains(chain) else { return true }
            let pattern = "(?<![a-z])" + NSRegularExpression.escapedPattern(for: chain) + "(?![a-z])"
            if lower.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        if keywords.contains(where: { lower.contains($0) }) { return true }
        let range = NSRange(text.startIndex..., in: text)
        // "from|at [the] Capitalised"
        if let regex = try? NSRegularExpression(pattern: #"\b(?:from|at)\s+(?:the\s+)?([A-Z][\w'’&.-]*)"#, options: [.caseInsensitive]) {
            for match in regex.matches(in: text, range: range) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let word = String(text[r])
                // The capital letter must be real (the pattern is case-insensitive on from/at only below).
                if word.first?.isUppercase == true, !notPlaces.contains(word) { return true }
            }
        }
        // Capitalised possessive: Wendy's, Joe's Pizza
        if let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-z]+['’]s\b"#) {
            for match in regex.matches(in: text, range: range) {
                guard let r = Range(match.range, in: text) else { continue }
                if !family.contains(String(text[r])) { return true }
            }
        }
        return false
    }
}

// MARK: - Prompt

/// Everything the model call needs, built without any network so it can be tested.
struct NutritionAIRequest {
    var systemPrompt: String
    var messages: [ChatMessage]
    var options: AIRequestOptions
}

enum NutritionAIPrompt {

    static func build(text: String, imageJPEG: Data?, context: AIMealContext?) -> NutritionAIRequest {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = RestaurantSignal.mentionsRestaurant(trimmed)
        var options = AIRequestOptions.forTask(.nutrition)
        options.googleSearch = search

        var system = """
        You are the nutrition estimator inside a food diary app. Reply with ONE JSON object and nothing else: \
        no markdown fences, no commentary before or after.

        Schema:
        {"items":[{"name":string,"restaurant":string|null,"brand":string|null,"portion_text":string,"servings":number,\
        "full_item":{"serving_label":string,"kcal":number,"protein_g":number,"carbs_g":number,"fat_g":number,\
        "fiber_g":number|null,"sugar_g":number|null,"sodium_mg":number|null,"sat_fat_g":number|null},\
        "confidence":"low"|"medium"|"high","notes":string}],"clarifying_question":string|null}

        Rules:
        - One item per distinct food or menu item. Maximum 12 items.
        - full_item is the nutrition of ONE FULL item or serving (the whole burrito bowl, one cup of yogurt, one \
        28 g handful of almonds), NOT what the user ate. serving_label says what that full item is ("1 bowl").
        - servings is the multiplier of the full item that the user ate: "half" = 0.5, "two" = 2, "a third" = 0.33. \
        Default 1. The app multiplies the nutrients by servings, so never pre-scale full_item.
        - portion_text repeats the user's portion words ("half", "2 strawberries"); use "" if none.
        - Grams for protein, carbs, fat, fiber, sugar and sat_fat; milligrams for sodium. Use null when unknown.
        - kcal should agree with the macros (4 kcal per g protein and carbs, 9 per g fat).
        - confidence: high only for published or very standard values, low for guesses.
        - notes: one short sentence on assumptions (sizes, what is included). No URLs.
        - If you cannot estimate without more detail, return items [] and a short clarifying_question.
        """
        if search {
            system += """

            - A restaurant or chain is mentioned. Use Google Search to find that restaurant's published nutrition \
            information or menu for the item, set "restaurant" to its name, and use the published values for \
            full_item. If you cannot find them, estimate from similar items, say so in notes, and use low or medium \
            confidence.
            """
        } else {
            system += """

            - Estimate from standard nutrition data (USDA-style values for typical portions).
            """
        }
        if imageJPEG != nil {
            system += """

            - A photo of the meal is attached. Identify each visible food and estimate the portion size. If the \
            user's text conflicts with the photo, trust the text.
            """
        }

        var user = trimmed.isEmpty ? "Estimate the meal in the photo." : "What I ate: \(trimmed)"
        if !trimmed.isEmpty, imageJPEG != nil { user += "\n(A photo is attached.)" }
        if let meal = context?.mealName?.trimmingCharacters(in: .whitespacesAndNewlines), !meal.isEmpty {
            user += "\nMeal: \(meal)."
        }
        return NutritionAIRequest(
            systemPrompt: system,
            messages: [ChatMessage(role: .user, content: user, imageJPEG: imageJPEG)],
            options: options
        )
    }
}

// MARK: - Parser

/// Turns the model's text into items. Lenient on purpose: fences, prose around the JSON, numbers as strings,
/// missing fields.
enum NutritionAIParser {
    static let maxItems = 12
    static let maxServings = 20.0
    static let maxKcal = 20_000.0

    static func estimate(from reply: AIReply, usedSearch: Bool) throws -> AIMealEstimate {
        let parsed = try parse(reply.text, usedSearch: usedSearch)
        var result = parsed
        result.sources = reply.sources
        result.items = parsed.items.map { var item = $0; item.sources = reply.sources; return item }
        return result
    }

    static func parse(_ text: String, usedSearch: Bool = false) throws -> AIMealEstimate {
        guard let json = firstJSONObject(in: text),
              let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NutritionAIError.unparseable
        }
        let rawItems = (root["items"] as? [Any]) ?? (root["foods"] as? [Any]) ?? []
        let items = rawItems.compactMap { ($0 as? [String: Any]).flatMap(parseItem) }.prefix(maxItems)
        let question = string(root["clarifying_question"])
        // A root with neither a recognisable list nor a question is not our answer.
        if root["items"] == nil, root["foods"] == nil, question == nil { throw NutritionAIError.unparseable }
        if items.isEmpty && question == nil { throw NutritionAIError.empty }
        return AIMealEstimate(items: Array(items), clarifyingQuestion: question, usedSearch: usedSearch, sources: [])
    }

    /// The first balanced `{...}` in the text (string-aware), after dropping ``` fences.
    static func firstJSONObject(in text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
        let chars = Array(cleaned)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        for i in start..<chars.count {
            let ch = chars[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(chars[start...i]) }
            }
        }
        return nil
    }

    private static func parseItem(_ raw: [String: Any]) -> AIMealItem? {
        guard let name = string(raw["name"]) ?? string(raw["food"]) else { return nil }
        let nutrition = (raw["full_item"] as? [String: Any]) ?? (raw["nutrition"] as? [String: Any]) ?? raw

        func num(_ keys: String...) -> Double? {
            for key in keys { if let v = number(nutrition[key]) { return v } }
            return nil
        }
        func nonNegative(_ v: Double?) -> Double? { v.map { max(0, $0) } }

        let protein = max(0, num("protein_g", "protein") ?? 0)
        let carbs = max(0, num("carbs_g", "carbs", "carbohydrates_g") ?? 0)
        let fat = max(0, num("fat_g", "fat") ?? 0)
        var kcal = min(maxKcal, max(0, num("kcal", "calories") ?? 0))
        if kcal == 0 { kcal = NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat) }

        var micros = Micronutrients()
        if let v = nonNegative(num("fiber_g", "fiber")) { micros[.fiber] = v }
        if let v = nonNegative(num("sugar_g", "sugar", "sugars_g")) { micros[.sugar] = v }
        if let v = nonNegative(num("sodium_mg", "sodium")) { micros[.sodium] = v }
        if let v = nonNegative(num("sat_fat_g", "saturated_fat_g", "sat_fat")) { micros[.satFat] = v }

        var servings = servingsValue(raw["servings"]) ?? 1
        if servings <= 0 { servings = 1 }
        servings = min(servings, maxServings)

        let label = string(nutrition["serving_label"]) ?? string(raw["serving_label"]) ?? "1 serving"
        return AIMealItem(
            name: name,
            restaurant: string(raw["restaurant"]),
            brand: string(raw["brand"]),
            portionText: string(raw["portion_text"]) ?? "",
            servings: servings,
            servingLabel: label,
            fullItem: NutrientValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat, micros: micros),
            confidence: string(raw["confidence"]).flatMap { AIConfidence(rawValue: $0.lowercased()) } ?? .medium,
            notes: string(raw["notes"]) ?? ""
        )
    }

    // MARK: Value helpers

    static func string(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.lowercased() == "null" ? nil : t
    }

    /// 12, 12.5, "12", "12 g", "1,200" -> number. NaN/infinite and booleans are not numbers.
    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        guard let s = value as? String else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"-?\d[\d,]*(?:\.\d+)?|-?\.\d+"#),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(match.range, in: s) else { return nil }
        let d = Double(s[r].replacingOccurrences(of: ",", with: ""))
        return d.flatMap { $0.isFinite ? $0 : nil }
    }

    /// Servings can arrive as 0.5, "0.5", "1/2" or "half".
    static func servingsValue(_ value: Any?) -> Double? {
        if let s = value as? String {
            let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "half" { return 0.5 }
            if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*/\s*(\d+)"#),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let a = Range(match.range(at: 1), in: lower), let b = Range(match.range(at: 2), in: lower),
               let n = Double(lower[a]), let d = Double(lower[b]), d != 0 {
                return n / d
            }
        }
        return number(value)
    }
}
