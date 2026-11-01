import SwiftUI

// MARK: - Formatting

enum JournalFormat {
    /// Local "yyyy-MM-dd", used for accessibility identifiers.
    static func dayId(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func title(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Emoji picked from the food's name. Purely decorative.
    static func emoji(for name: String) -> String {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("egg", "🥚"), ("yogurt", "🥛"), ("yoghurt", "🥛"), ("milk", "🥛"), ("oat", "🥣"), ("cereal", "🥣"),
            ("chicken", "🍗"), ("beef", "🥩"), ("steak", "🥩"), ("jerky", "🥩"), ("rice", "🍚"), ("bread", "🍞"),
            ("toast", "🍞"), ("pasta", "🍝"), ("spaghetti", "🍝"), ("coffee", "☕️"), ("latte", "☕️"),
            ("banana", "🍌"), ("apple", "🍎"), ("salad", "🥗"), ("fish", "🐟"), ("salmon", "🐟"), ("cheese", "🧀"),
            ("potato", "🥔"), ("pizza", "🍕"), ("burger", "🍔"), ("nut", "🥜"), ("almond", "🥜"), ("protein", "🥤")
        ]
        return table.first { n.contains($0.0) }?.1 ?? "🍽️"
    }
}

// MARK: - Macro text

/// "P12  C0  F10  🔥140" coloured like the macro rings.
struct MacroSummaryLine: View {
    let nutrients: NutrientValues
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: 10) {
            Text("P\(NutritionFormat.whole(nutrients.protein))").foregroundStyle(AppTheme.macroProtein)
            Text("C\(NutritionFormat.whole(nutrients.carbs))").foregroundStyle(AppTheme.macroCarbs)
            Text("F\(NutritionFormat.whole(nutrients.fat))").foregroundStyle(AppTheme.macroFat)
            HStack(spacing: 2) {
                Image(systemName: "flame").imageScale(.small)
                Text(NutritionFormat.whole(nutrients.kcal))
            }
            .foregroundStyle(AppTheme.macroKcal)
        }
        .font(font)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(NutritionFormat.whole(nutrients.protein)), carbs \(NutritionFormat.whole(nutrients.carbs)), fat \(NutritionFormat.whole(nutrients.fat)), \(NutritionFormat.whole(nutrients.kcal)) calories")
    }
}

/// Four small tinted chips (P C F kcal) for a meal card.
struct MacroChipRow: View {
    let totals: NutrientValues

    var body: some View {
        HStack(spacing: 8) {
            chip("P\(NutritionFormat.whole(totals.protein))", AppTheme.macroProtein)
            chip("C\(NutritionFormat.whole(totals.carbs))", AppTheme.macroCarbs)
            chip("F\(NutritionFormat.whole(totals.fat))", AppTheme.macroFat)
            HStack(spacing: 3) {
                Image(systemName: "flame").imageScale(.small)
                Text(NutritionFormat.whole(totals.kcal))
            }
            .modifier(ChipStyle(color: AppTheme.macroKcal))
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(NutritionFormat.whole(totals.protein)), carbs \(NutritionFormat.whole(totals.carbs)), fat \(NutritionFormat.whole(totals.fat)), \(NutritionFormat.whole(totals.kcal)) calories")
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).modifier(ChipStyle(color: color))
    }

    private struct ChipStyle: ViewModifier {
        let color: Color
        func body(content: Content) -> some View {
            content
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.macroTint(color), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Ring

struct MacroRing: View {
    let color: Color
    let progress: Double
    let primary: String
    let secondary: String
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle().stroke(AppTheme.macroTint(color), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(primary).font(.headline.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text(secondary).font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: size, height: size)
    }
}

/// Small circle with a letter and "x of y", used in the compact (scrolled) header.
struct MiniMacro: View {
    let letter: String
    let icon: String?
    let color: Color
    let value: Double
    let target: Double?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(AppTheme.macroTint(color), lineWidth: 3)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let icon { Image(systemName: icon).font(.caption2).foregroundStyle(color) }
                else { Text(letter).font(.caption.weight(.bold)).foregroundStyle(color) }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(NutritionFormat.whole(value)).font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                Text(target.map { "of \(NutritionFormat.whole($0))" } ?? "no goal")
                    .font(.caption2).foregroundStyle(AppTheme.textSecondary)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(1, value / target)
    }
}

// MARK: - Buttons

/// Round tinted "+" used on cards and rows.
struct RoundPlusButton: View {
    var systemName = "plus"
    var filled = false
    let id: String
    var label: String = "Add"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? AppTheme.onAccent : AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(filled ? AppTheme.accent : AppTheme.accent.opacity(0.16), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Round white/elevated button (the card "…" menu and the bar icons).
struct RoundIcon: View {
    let systemName: String
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: size, height: size)
            .background(AppTheme.surfaceElevated, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

/// Filter chip row (All / Recipes / Meals / Foods).
enum FoodFilter: String, CaseIterable, Identifiable {
    case all = "All", recipes = "Recipes", meals = "Meals", foods = "Foods"
    var id: String { rawValue }
}

struct FoodFilterChips: View {
    @Binding var selection: FoodFilter
    let idPrefix: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FoodFilter.allCases) { filter in
                Button { selection = filter } label: {
                    Text(filter.rawValue)
                        .font(.body.weight(selection == filter ? .semibold : .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(AppTheme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selection == filter ? AppTheme.textPrimary : AppTheme.border,
                                                        lineWidth: selection == filter ? 1.5 : 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == filter ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).chip.\(filter.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Search bar

/// Pill-shaped search field used at the bottom of Journal, add-food and Kitchen.
struct PillSearchField: View {
    @Binding var text: String
    let prompt: String
    let id: String
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textPrimary).accessibilityHidden(true)
            field
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(AppTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder private var field: some View {
        let base = TextField(prompt, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier(id)
        if let focus { base.focused(focus) } else { base }
    }
}

// MARK: - Swipe to delete

/// Reveals a Delete button when the row is dragged left. The row needs an opaque background.
struct SwipeToDelete: ViewModifier {
    let id: String
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    private let revealWidth: CGFloat = 76

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.destructive)
            }
            .opacity(offset < -8 ? 1 : 0)
            .allowsHitTesting(offset < -revealWidth / 2)
            .accessibilityLabel("Delete")
            .accessibilityIdentifier(id)

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-revealWidth * 1.3, value.translation.width + (offset <= -revealWidth ? -revealWidth : 0)))
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = value.translation.width < -revealWidth / 2 ? -revealWidth : 0
                            }
                        }
                )
        }
        .clipped()
        .accessibilityAction(named: "Delete", onDelete)
    }
}

extension View {
    func swipeToDelete(id: String, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(id: id, onDelete: onDelete))
    }
}

// MARK: - Food row

/// One saved food: emoji, name, serving › macros, trailing accessory.
struct FoodRowView<Accessory: View>: View {
    let food: NutritionFood
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Text(JournalFormat.emoji(for: food.name))
                .font(.system(size: 30))
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(food.servingLabel)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    MacroSummaryLine(nutrients: food.nutrients, font: .subheadline.weight(.semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}
