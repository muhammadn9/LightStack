import SwiftUI

// MARK: - Serving target

/// What the serving screen shows: a branded product not saved yet, or a food already in the Kitchen.
struct ServingTarget {
    var name: String
    var brand: String?
    var imageURL: URL?
    var servingLabel: String
    var nutrients: NutrientValues
    var per100Only: Bool
    var warnings: [OpenFoodFactsWarning]
    var isBranded: Bool

    init(product: OpenFoodFactsProduct) {
        name = product.name; brand = product.brand; imageURL = product.imageURL
        servingLabel = product.servingLabel; nutrients = product.nutrients
        per100Only = product.warnings.contains(.per100Only); warnings = product.warnings; isBranded = true
    }

    init(food: NutritionFood) {
        name = food.name; brand = food.brand; imageURL = nil
        servingLabel = food.servingLabel; nutrients = food.nutrients
        per100Only = false; warnings = []; isBranded = food.barcode != nil && food.source == .openFoodFacts
    }
}

extension OpenFoodFactsWarning {
    /// Short note for the badge and the serving screen; nil for warnings shown another way.
    var note: String? {
        switch self {
        case .kcalFromKilojoules: return "Calories converted from kilojoules"
        case .kcalFromMacros: return "Calories estimated from protein, carbs and fat"
        case .missingMacros: return "Some nutrients are missing and count as 0"
        case .per100Only: return nil
        }
    }
}

enum OpenFoodFactsAttribution {
    static let text = "Data from Open Food Facts (ODbL)"
    static let url = URL(string: "https://world.openfoodfacts.org")
}

// MARK: - Search results section

/// The "Branded" block under the local results while typing a search.
struct BrandedResultsSection: View {
    let state: BrandedSearchState
    let onSelect: (OpenFoodFactsProduct) -> Void
    let onRetry: () -> Void

    var body: some View {
        if state != .idle {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "tag").foregroundStyle(AppTheme.textSecondary)
                    Text("Branded").font(.headline).foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) { content }
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                Text(OpenFoodFactsAttribution.text)
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("addfood.branded.attribution")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Searching branded foods…").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(14).frame(minHeight: 56)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("addfood.branded.loading")
        case .empty:
            Text("No branded foods found.")
                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).frame(minHeight: 56)
                .accessibilityIdentifier("addfood.branded.empty")
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.subheadline).foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("addfood.branded.error")
                Button(action: onRetry) {
                    Text("Retry").font(.body.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("addfood.branded.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        case .results(let products):
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                if index > 0 { Divider().padding(.leading, 70) }
                Button { onSelect(product) } label: { BrandedRow(product: product) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addfood.branded.\(product.name)")
                    .accessibilityHint("Choose servings")
            }
        }
    }
}

private struct BrandedRow: View {
    let product: OpenFoodFactsProduct

    private var badge: String? { product.warnings.compactMap(\.note).first }

    var body: some View {
        HStack(spacing: 12) {
            Text(JournalFormat.emoji(for: product.name))
                .font(.system(size: 30)).frame(width: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.body.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let brand = product.brand {
                    Text(brand).font(.footnote).foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(product.hasServingSize ? product.servingLabel : "per \(product.servingLabel)")
                        .foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    MacroSummaryLine(nutrients: product.nutrients)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 4)
            if badge != nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityLabel(badge ?? "")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - Serving screen

/// Name, brand, picture, servings and a live macro preview, with "Add to <meal>" (and optionally "Add to plate").
/// The caller wraps it in a NavigationStack and decides what adding does.
struct BrandedServingView: View {
    let target: ServingTarget
    let mealName: String
    let onAdd: (Double) -> Void
    var onPlate: ((Double) -> Void)?

    @State private var text = "1"

    private var servings: Double? { NutritionFormat.parse(text).flatMap { $0 > 0 ? $0 : nil } }

    private func step(_ delta: Double) {
        let next = max(0.5, (servings ?? 1) + delta)
        text = NutritionFormat.amount(next)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                            .accessibilityIdentifier("branded.name")
                        if let brand = target.brand {
                            Text(brand).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        }
                        Text(target.per100Only ? "Values per \(target.servingLabel)" : "Per \(target.servingLabel)")
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("branded.serving")
                    }
                }
                .frame(minHeight: 44)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                HStack(spacing: 0) {
                    NutritionField(title: "Servings", unit: "", text: $text, id: "branded.servings.field", placeholder: "1")
                    Button { step(-0.5) } label: {
                        Image(systemName: "minus.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Fewer servings")
                    .accessibilityIdentifier("branded.servings.dec")
                    Button { step(0.5) } label: {
                        Image(systemName: "plus.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("More servings")
                    .accessibilityIdentifier("branded.servings.inc")
                }
                .foregroundStyle(AppTheme.accent)
                if let servings {
                    MacroSummaryLine(nutrients: target.nutrients.scaled(by: servings))
                        .accessibilityIdentifier("branded.summary")
                }
            }
            .listRowBackground(AppTheme.surface)

            if target.per100Only || target.warnings.contains(where: { $0.note != nil }) {
                Section {
                    if target.per100Only {
                        Label("No serving size on record, so values are per \(target.servingLabel). Set servings to match what you ate.",
                              systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                    ForEach(target.warnings.compactMap(\.note), id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }

            if target.isBranded {
                Section {
                    if let url = OpenFoodFactsAttribution.url {
                        Link(OpenFoodFactsAttribution.text, destination: url)
                            .font(.footnote).frame(minHeight: 44, alignment: .leading)
                    } else {
                        Text(OpenFoodFactsAttribution.text).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .listRowBackground(AppTheme.surface)
                .accessibilityIdentifier("branded.attribution")
            }
        }
        .nutritionFormStyle()
        .navigationTitle("Add food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .keyboardDoneButton()
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = target.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: Text(JournalFormat.emoji(for: target.name)).font(.largeTitle)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Text(JournalFormat.emoji(for: target.name)).font(.largeTitle).frame(width: 56).accessibilityHidden(true)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                if let servings { onAdd(servings) }
            } label: {
                Text("Add to \(mealName)")
                    .font(.headline).foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(servings == nil ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(servings == nil)
            .accessibilityIdentifier("branded.add")
            if let onPlate {
                Button {
                    if let servings { onPlate(servings) }
                } label: {
                    Text("Add to plate")
                        .font(.headline).foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                }
                .buttonStyle(.plain)
                .disabled(servings == nil)
                .accessibilityIdentifier("branded.plate")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppTheme.background)
    }
}
