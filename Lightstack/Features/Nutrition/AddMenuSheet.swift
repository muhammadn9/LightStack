import SwiftUI

/// The "+" sheet: search, quick actions and creators. Unbuilt creators are shown but disabled.
struct AddMenuSheet: View {
    let onSearch: (String) -> Void
    let onWater: () -> Void
    let onQuickTrack: () -> Void
    let onCreateFood: () -> Void

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textPrimary)
                        TextField("Food search", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { onSearch(query) }
                            .accessibilityIdentifier("addmenu.search")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 0.5))
                    roundDisabled("sparkles", id: "addmenu.ai", label: "AI search, coming soon")
                    roundDisabled("barcode.viewfinder", id: "addmenu.barcode", label: "Barcode, coming soon")
                }

                HStack(spacing: 12) {
                    tile("scalemass.fill", AppTheme.trackerWater, "Log weight", id: "addmenu.weight", enabled: false, action: {})
                    tile("drop.fill", AppTheme.waterBlue, "Log water", id: "addmenu.water", enabled: true, action: onWater)
                    tile("bolt.fill", AppTheme.quickTrackGreen, "Quick Track", id: "addmenu.quickTrack", enabled: true, action: onQuickTrack)
                }

                VStack(spacing: 0) {
                    row("carrot", "Create Food", id: "addmenu.createFood", enabled: true, action: onCreateFood)
                    Divider().padding(.leading, 64)
                    row("fork.knife", "Create Meal", id: "addmenu.createMeal", enabled: false, action: {})
                    Divider().padding(.leading, 64)
                    row("frying.pan", "Create Recipe", id: "addmenu.createRecipe", enabled: false, action: {})
                    Divider().padding(.leading, 64)
                    row("wineglass", "Create Alcoholic Bev", id: "addmenu.createBev", enabled: false, action: {})
                }
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private func roundDisabled(_ icon: String, id: String, label: String) -> some View {
        Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.textSecondary)
            .frame(width: 48, height: 48)
            .background(AppTheme.surface, in: Circle())
            .opacity(0.5)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
    }

    private func tile(_ icon: String, _ color: Color, _ title: String, id: String, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(color, in: Circle())
                Text(title).font(.subheadline).foregroundStyle(AppTheme.textPrimary)
                if !enabled { Text("Coming soon").font(.caption2).foregroundStyle(AppTheme.textSecondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }

    private func row(_ icon: String, _ title: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.textPrimary).frame(width: 32)
                Text(title).font(.title3).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if !enabled { Text("Coming soon").font(.caption).foregroundStyle(AppTheme.textSecondary) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}

/// Log water: quick amounts in the chosen unit, or a custom amount.
struct WaterSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    private var quickAmounts: [Int] { viewModel.waterUnit == .flOz ? [8, 12, 16, 24] : [250, 330, 500, 750] }
    private var customValue: Double? { NutritionFormat.parse(custom).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Quick add").font(.headline).foregroundStyle(AppTheme.textPrimary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(quickAmounts, id: \.self) { amount in
                        Button {
                            viewModel.addWater(ml: viewModel.waterUnit.toMl(Double(amount)))
                            dismiss()
                        } label: {
                            Label("+\(amount) \(viewModel.waterUnit.label)", systemImage: "drop.fill")
                                .font(.headline)
                                .foregroundStyle(AppTheme.waterBlue)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(AppTheme.waterBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("journal.water.quick.\(amount)")
                    }
                }
                Text("Custom").font(.headline).foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 10) {
                    HStack {
                        TextField("Amount", text: $custom)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("journal.water.custom")
                        Text(viewModel.waterUnit.label).foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        guard let customValue else { return }
                        viewModel.addWater(ml: viewModel.waterUnit.toMl(customValue))
                        dismiss()
                    } label: {
                        Text("Add").font(.headline).foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 22).frame(minHeight: 48)
                            .background(customValue == nil ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(customValue == nil)
                    .accessibilityIdentifier("journal.water.custom.add")
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Log water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// Create a food by hand (the review form with empty fields).
struct CreateFoodView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var mealSlotId: UUID?
    var logByDefault = true
    var onLogged: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FoodReviewView(viewModel: viewModel, mealSlotId: mealSlotId, logByDefault: logByDefault,
                           parsed: NutritionLabelParser.parse(text: "")) {
                onLogged?()
                dismiss()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .keyboardDoneButton()
    }
}
