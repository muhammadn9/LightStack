import SwiftUI

/// Saved foods. Only Foods has data this phase; Recipes and Meals are placeholders.
struct KitchenView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var filter: FoodFilter = .all
    @State private var query = ""
    @State private var foods: [NutritionFood] = []
    @State private var editing: NutritionFood?
    @State private var creating = false

    private var showsFoods: Bool { filter == .all || filter == .foods }

    var body: some View {
        VStack(spacing: 0) {
            NutritionScreenHeader(title: "Kitchen", id: "kitchen.title")
            FoodFilterChips(selection: $filter, idPrefix: "kitchen")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !showsFoods {
                        Text("\(filter.rawValue) are coming soon.")
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("kitchen.soon")
                    } else if foods.isEmpty {
                        Text(query.isEmpty ? "No saved foods yet. Tap + to create one or scan a label from the Journal."
                                           : "No saved foods match.")
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("kitchen.empty")
                    } else {
                        Text("Saved").font(.headline).foregroundStyle(AppTheme.textPrimary).padding(.horizontal, 20)
                        VStack(spacing: 0) {
                            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                                if index > 0 { Divider().padding(.leading, 70) }
                                row(food)
                            }
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                PillSearchField(text: $query, prompt: "Search food", id: "kitchen.search")
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 0.5))
                }
                .accessibilityLabel("Create food")
                .accessibilityIdentifier("kitchen.create")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(item: $editing) { food in FoodEditView(viewModel: viewModel, food: food) }
        .sheet(isPresented: $creating) { CreateFoodView(viewModel: viewModel, logByDefault: false) }
        .onAppear(perform: reload)
        .onChange(of: query) { _, _ in reload() }
        .onChange(of: viewModel.foodsVersion) { _, _ in reload() }
    }

    private func row(_ food: NutritionFood) -> some View {
        HStack(spacing: 0) {
            Button { editing = food } label: { FoodRowView(food: food) { EmptyView() } }
                .buttonStyle(.plain)
                .accessibilityIdentifier("kitchen.food.\(food.name)")
            Button { viewModel.setFavorite(food, !food.isFavorite) } label: {
                Image(systemName: food.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(food.isFavorite ? AppTheme.warning : AppTheme.textSecondary)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(food.isFavorite ? "Remove \(food.name) from favourites" : "Add \(food.name) to favourites")
            .accessibilityIdentifier("kitchen.favorite.\(food.name)")
        }
    }

    private func reload() {
        foods = viewModel.searchFoods(query)
    }
}

/// Edit or delete a saved food (name, serving, per-serving macros, favourite).
struct FoodEditView: View {
    @ObservedObject var viewModel: NutritionViewModel
    let food: NutritionFood
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var servingLabel = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var favourite = false
    @State private var loaded = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && NutritionFormat.parse(kcal) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).frame(minHeight: 44).accessibilityIdentifier("kitchen.edit.name")
                    TextField("Serving (e.g. 1 cup)", text: $servingLabel).frame(minHeight: 44)
                        .accessibilityIdentifier("kitchen.edit.serving")
                    Toggle("Favourite", isOn: $favourite).tint(AppTheme.accent)
                        .accessibilityIdentifier("kitchen.edit.favourite")
                }
                .listRowBackground(AppTheme.surface)
                Section {
                    NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "kitchen.edit.kcal")
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "kitchen.edit.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "kitchen.edit.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "kitchen.edit.fat")
                } header: { Text("Per serving") }
                .listRowBackground(AppTheme.surface)
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteFood(food)
                        dismiss()
                    } label: { Label("Delete food", systemImage: "trash").frame(minHeight: 44) }
                    .accessibilityIdentifier("kitchen.edit.delete")
                }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("kitchen.edit.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = food.name
                servingLabel = food.servingLabel
                kcal = NutritionFormat.field(food.nutrients.kcal)
                protein = NutritionFormat.field(food.nutrients.protein)
                carbs = NutritionFormat.field(food.nutrients.carbs)
                fat = NutritionFormat.field(food.nutrients.fat)
                favourite = food.isFavorite
            }
        }
        .keyboardDoneButton()
    }

    private func save() {
        var updated = food
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { updated.servingLabel = label }
        updated.nutrients.kcal = max(0, NutritionFormat.parse(kcal) ?? food.nutrients.kcal)
        updated.nutrients.protein = max(0, NutritionFormat.parse(protein) ?? 0)
        updated.nutrients.carbs = max(0, NutritionFormat.parse(carbs) ?? 0)
        updated.nutrients.fat = max(0, NutritionFormat.parse(fat) ?? 0)
        updated.isFavorite = favourite
        viewModel.updateFood(updated)
        dismiss()
    }
}
