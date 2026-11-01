import SwiftUI

/// A labelled number field row used by every nutrition form. `flagged` marks a value the user should check
/// (colour + icon + VoiceOver hint, never colour alone).
struct NutritionField: View {
    let title: String
    let unit: String
    @Binding var text: String
    let id: String
    var flagged: Bool = false
    var flagID: String?
    var placeholder: String = "0"
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        HStack(spacing: 8) {
            if flagged {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(flagID ?? "\(id).flag")
            }
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70, maxWidth: 120, minHeight: 44)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityLabel(title)
                .accessibilityHint(flagged ? "Check this value" : "")
                .accessibilityIdentifier(id)
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minWidth: 28, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, flagged ? 8 : 0)
        .background(flagged ? AppTheme.warning.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if flagged {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.warning, lineWidth: 1.5)
            }
        }
    }
}

/// Wraps content in the app's themed form chrome.
struct NutritionFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .keyboardDoneButton()
    }
}

extension View {
    func nutritionFormStyle() -> some View { modifier(NutritionFormStyle()) }
}

/// Micronutrient inputs keyed by `MicroKey`; blank means unknown.
struct MicroFieldsSection: View {
    @Binding var values: [MicroKey: String]
    let idPrefix: String

    var body: some View {
        ForEach(MicroKey.allCases, id: \.self) { key in
            NutritionField(
                title: NutritionFormat.microLabel(key), unit: key.unit,
                text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }),
                id: "\(idPrefix).\(key.rawValue)", placeholder: "—"
            )
            .listRowBackground(AppTheme.surface)
        }
    }
}

extension Micronutrients {
    /// Builds micros from text inputs; blank or unparsable stays unknown.
    init(texts: [MicroKey: String]) {
        self.init()
        for (key, text) in texts {
            if let v = NutritionFormat.parse(text), v >= 0 { values[key] = v }
        }
    }
}
