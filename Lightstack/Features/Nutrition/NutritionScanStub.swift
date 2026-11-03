#if DEBUG
import SwiftUI

/// UI-test replacement for the camera scanner. Injects a fixture OCR string chosen with
/// `-nutritionScanFixture <name>` (default `us_standard`). DEBUG builds only.
struct ScanStubView: View {
    let onUse: ([OCRLine]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.viewfinder").font(.largeTitle).foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text("Scanner stub (\(NutritionScanFixtures.selectedName))")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Button {
                let text = NutritionScanFixtures.selectedText
                onUse(text.split(whereSeparator: \.isNewline).map { OCRLine(text: String($0)) })
            } label: {
                Text("Use this")
                    .font(.headline)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(AppTheme.accent, in: Capsule())
            }
            .accessibilityIdentifier("nutrition.scan.use")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

enum NutritionScanFixtures {
    static var selectedName: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-nutritionScanFixture"), i + 1 < args.count else { return "us_standard" }
        return args[i + 1]
    }

    static var selectedText: String { all[selectedName] ?? all["us_standard"] ?? "" }

    static let all: [String: String] = [
        "us_standard": """
        Nutrition Facts
        2 servings per container
        Serving size 1 cup (228g)
        Amount per serving
        Calories 250
        % Daily Value*
        Total Fat 12g 18%
        Saturated Fat 3g 15%
        Trans Fat 3g
        Cholesterol 30mg 10%
        Sodium 470mg 20%
        Total Carbohydrate 31g 10%
        Dietary Fiber 0g 0%
        Total Sugars 5g
        Protein 5g
        """,
        // Calories do not match the macros, so those fields come back low confidence.
        "macro_inconsistent": """
        Nutrition Facts
        Serving size 1 pack (50g)
        Calories 400
        Total Fat 5g
        Total Carbohydrate 20g
        Protein 5g
        """,
        "per100ml_drink": """
        Nutrition Information
        Typical values per 100ml
        Energy 180kJ/42kcal
        Fat 0g
        of which saturates 0g
        Carbohydrate 10.6g
        of which sugars 10.6g
        Protein 0g
        Salt 0.01g
        """,
        "eu_dual_column": """
        Nutrition information
        Typical values per 100g per 30g serving
        Energy 1046kJ/250kcal 314kJ/75kcal
        Fat 10.0g 3.0g
        of which saturates 2.0g 0.6g
        Carbohydrate 30.0g 9.0g
        of which sugars 5.0g 1.5g
        Fibre 4.0g 1.2g
        Protein 8.0g 2.4g
        Salt 0.9g 0.27g
        """,
        "per100g_only": """
        Nutrition Information
        Typical values per 100g
        Energy 1046kJ/250kcal
        Fat 10.0g
        of which saturates 2.0g
        Carbohydrate 30.0g
        of which sugars 5.0g
        Protein 8.0g
        Salt 0.9g
        """
    ]
}
#endif
