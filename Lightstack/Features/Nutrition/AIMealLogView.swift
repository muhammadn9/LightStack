import SwiftUI
import PhotosUI
import UIKit

// MARK: - Shared AI badges

/// Small "AI estimate" marker for foods whose values came from the AI.
struct AIEstimateBadge: View {
    var body: some View {
        Label("AI estimate", systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.accent.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("food.aiBadge")
    }
}

/// Tappable source links for an AI estimate.
struct AISourceLinks: View {
    let sources: [AIFoodSource]
    var idPrefix = "ai.source"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.caption)
                            Text(Self.label(for: source, url: url))
                                .font(.footnote)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityIdentifier("\(idPrefix).\(index)")
                }
            }
        }
    }

    private static func label(for source: AIFoodSource, url: URL) -> String {
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return url.host ?? source.url
    }
}

// MARK: - Camera

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - AI meal log

/// Describe a meal (and/or add a photo), get an AI estimate, edit it, then log it. Nothing is logged until the
/// user taps the log button.
struct AIMealLogView: View {
    @ObservedObject var viewModel: NutritionViewModel
    var initialText = ""
    var initialSlotId: UUID?
    var onLogged: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var imageData: Data?
    @State private var slotId: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var items: [AIMealItem] = []
    @State private var estimate: AIMealEstimate?
    @State private var answer = ""
    @State private var submittedText = ""
    @State private var editingIndex: Int?
    @State private var loaded = false

    private var canEstimate: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageData != nil
    }
    private var slotName: String { viewModel.slot(id: slotId)?.name ?? "Meal" }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch viewModel.aiState {
                    case .idle:
                        inputSection
                    case .working:
                        workingSection
                    case .result:
                        resultSection
                    case .error(let message):
                        errorSection(message)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Log with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("ai.close")
                }
            }
        }
        .keyboardDoneButton()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            viewModel.resetAIEstimate()
            text = initialText
            slotId = initialSlotId ?? viewModel.defaultSlotId
        }
        .onDisappear { viewModel.resetAIEstimate() }
        .onChange(of: viewModel.aiState) { _, state in
            if case .result(let result) = state {
                estimate = result
                items = result.items
                answer = ""
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self) { imageData = data }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { imageData = $0 }.ignoresSafeArea()
        }
        .sheet(item: Binding(
            get: { editingIndex.flatMap { items.indices.contains($0) ? EditTarget(index: $0) : nil } },
            set: { editingIndex = $0?.index }
        )) { target in
            AIItemEditSheet(item: $items[target.index], index: target.index)
        }
    }

    private struct EditTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    // MARK: Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Describe what you ate, e.g. half a chicken burrito bowl from Chipotle",
                      text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 0.5))
                .accessibilityIdentifier("ai.input")

            photoRow

            HStack {
                Text("Meal").font(.headline).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Picker("Meal", selection: $slotId) {
                    ForEach(viewModel.slots) { slot in Text(slot.name).tag(UUID?.some(slot.id)) }
                }
                .tint(AppTheme.accent)
                .accessibilityIdentifier("ai.mealPicker")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                submittedText = text
                viewModel.estimateMeal(text: text, image: imageData, mealSlotId: slotId)
            } label: {
                Text("Estimate")
                    .font(.headline)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(canEstimate ? AppTheme.accent : AppTheme.textSecondary.opacity(0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canEstimate)
            .accessibilityIdentifier("ai.estimate")
        }
    }

    private var photoRow: some View {
        HStack(spacing: 12) {
            if let imageData, let image = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("ai.photo.thumb")
                    Button { self.imageData = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                            .frame(width: 44, height: 44)
                    }
                    .offset(x: 14, y: -14)
                    .accessibilityLabel("Remove photo")
                    .accessibilityIdentifier("ai.photo.remove")
                }
                .frame(width: 72, height: 72)
            }
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Camera", systemImage: "camera")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(AppTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.photo.camera")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photo", systemImage: "photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(AppTheme.surface, in: Capsule())
            }
            .accessibilityIdentifier("ai.photo.library")
            Spacer(minLength: 0)
        }
    }

    // MARK: Working

    private var workingSection: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(AppTheme.accent)
            Text(RestaurantSignal.mentionsRestaurant(submittedText) ? "Searching the web…" : "Estimating…")
                .font(.headline).foregroundStyle(AppTheme.textPrimary)
            Button("Cancel") { viewModel.cancelAIEstimate() }
                .font(.headline)
                .frame(minHeight: 44)
                .accessibilityIdentifier("ai.cancel")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.working")
    }

    // MARK: Error

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("ai.error")
            HStack(spacing: 10) {
                Button {
                    viewModel.estimateMeal(text: submittedText, image: imageData, mealSlotId: slotId)
                } label: {
                    Text("Retry").font(.headline).foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 22).frame(minHeight: 48)
                        .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.retry")
                Button("Start over") { startOver() }
                    .font(.headline).frame(minHeight: 48)
                    .accessibilityIdentifier("ai.startOver")
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Result

    private var total: NutrientValues {
        items.reduce(NutrientValues()) { acc, item in
            let e = item.eaten
            return NutrientValues(kcal: acc.kcal + e.kcal, protein: acc.protein + e.protein,
                                  carbs: acc.carbs + e.carbs, fat: acc.fat + e.fat)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let question = estimate?.clarifyingQuestion {
                questionBanner(question)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                itemCard(index)
            }
            if !items.isEmpty {
                HStack {
                    Text("Total").font(.headline).foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("\(NutritionFormat.whole(total.kcal)) kcal · P \(NutritionFormat.amount(total.protein)) · C \(NutritionFormat.amount(total.carbs)) · F \(NutritionFormat.amount(total.fat))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(14)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai.total")
            }
            if let estimate, estimate.usedSearch {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Web search was used to look up published nutrition information. Values are still estimates.")
                        .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    AISourceLinks(sources: estimate.sources, idPrefix: "ai.estimate.source")
                }
                .accessibilityIdentifier("ai.searchNote")
            }
            Button { logItems() } label: {
                Text("Log to \(slotName)").font(.headline).foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    .background(items.isEmpty ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)
            .accessibilityIdentifier("ai.log")
            Button("Start over") { startOver() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("ai.startOver")
        }
    }

    private func questionBanner(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(question, systemImage: "questionmark.bubble")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("ai.question")
            HStack(spacing: 10) {
                TextField("Your answer", text: $answer)
                    .submitLabel(.send)
                    .onSubmit(submitAnswer)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("ai.question.answer")
                Button(action: submitAnswer) {
                    Text("Send").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(answer.trimmingCharacters(in: .whitespaces).isEmpty ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("ai.question.send")
            }
        }
        .padding(14)
        .background(AppTheme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func itemCard(_ index: Int) -> some View {
        let item = items[index]
        let eaten = item.eaten
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).foregroundStyle(AppTheme.textPrimary)
                    if let venue = item.venue {
                        Text(venue).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                    if !item.portionText.isEmpty {
                        Text(item.portionText).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Button { editingIndex = index } label: {
                    Image(systemName: "pencil").foregroundStyle(AppTheme.textPrimary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Edit \(item.name)")
                .accessibilityIdentifier("ai.item.\(index).edit")
                Button { removeItem(at: index) } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.destructive).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove \(item.name)")
                .accessibilityIdentifier("ai.item.\(index).remove")
            }
            Stepper(value: Binding(
                get: { items.indices.contains(index) ? items[index].servings : 1 },
                set: { if items.indices.contains(index) { items[index].servings = $0 } }
            ), in: 0.25...50, step: 0.25) {
                Text("\(NutritionFormat.amount(item.servings)) × \(item.servingLabel)")
                    .font(.subheadline).foregroundStyle(AppTheme.textPrimary)
            }
            .accessibilityIdentifier("ai.item.\(index).servings")
            Text("\(NutritionFormat.whole(eaten.kcal)) kcal · P \(NutritionFormat.amount(eaten.protein)) · C \(NutritionFormat.amount(eaten.carbs)) · F \(NutritionFormat.amount(eaten.fat))")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("ai.item.\(index).macros")
            HStack(spacing: 8) {
                confidenceBadge(item.confidence)
                    .accessibilityIdentifier("ai.item.\(index).confidence")
            }
            if item.kcalLooksOff {
                Label("Calories don't match the macros. Check the numbers.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(AppTheme.warning)
                    .accessibilityIdentifier("ai.item.\(index).warning")
            }
            if !item.notes.isEmpty {
                Text(item.notes).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
            if !item.sources.isEmpty {
                DisclosureGroup("Sources (\(item.sources.count))") {
                    AISourceLinks(sources: item.sources, idPrefix: "ai.item.\(index).source")
                        .padding(.top, 6)
                }
                .font(.footnote)
                .tint(AppTheme.textSecondary)
                .accessibilityIdentifier("ai.item.\(index).sources")
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.item.\(index)")
    }

    private func confidenceBadge(_ confidence: AIConfidence) -> some View {
        let (label, color): (String, Color) = {
            switch confidence {
            case .high: return ("High confidence", AppTheme.success)
            case .medium: return ("Medium confidence", AppTheme.warning)
            case .low: return ("Low confidence", AppTheme.destructive)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Actions

    private func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    private func submitAnswer() {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let combined = submittedText + "\nAnswer: " + trimmed
        submittedText = combined
        viewModel.estimateMeal(text: combined, image: imageData, mealSlotId: slotId)
    }

    private func startOver() {
        viewModel.resetAIEstimate()
        items = []
        estimate = nil
        answer = ""
    }

    private func logItems() {
        guard !items.isEmpty else { return }
        viewModel.logAIItems(items, mealSlotId: slotId)
        onLogged?()
        dismiss()
    }
}

// MARK: - Item edit

private struct AIItemEditSheet: View {
    @Binding var item: AIMealItem
    let index: Int
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var loaded = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && NutritionFormat.parse(kcal) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).frame(minHeight: 44).accessibilityIdentifier("ai.edit.name")
                }
                .listRowBackground(AppTheme.surface)
                Section {
                    NutritionField(title: "Calories", unit: "kcal", text: $kcal, id: "ai.edit.kcal")
                    NutritionField(title: "Protein", unit: "g", text: $protein, id: "ai.edit.protein")
                    NutritionField(title: "Carbs", unit: "g", text: $carbs, id: "ai.edit.carbs")
                    NutritionField(title: "Fat", unit: "g", text: $fat, id: "ai.edit.fat")
                } header: { Text("Full item (\(item.servingLabel))") }
                .listRowBackground(AppTheme.surface)
            }
            .nutritionFormStyle()
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("ai.edit.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = item.name
                kcal = NutritionFormat.field(item.fullItem.kcal)
                protein = NutritionFormat.field(item.fullItem.protein)
                carbs = NutritionFormat.field(item.fullItem.carbs)
                fat = NutritionFormat.field(item.fullItem.fat)
            }
        }
        .keyboardDoneButton()
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.fullItem.kcal = max(0, NutritionFormat.parse(kcal) ?? item.fullItem.kcal)
        item.fullItem.protein = max(0, NutritionFormat.parse(protein) ?? 0)
        item.fullItem.carbs = max(0, NutritionFormat.parse(carbs) ?? 0)
        item.fullItem.fat = max(0, NutritionFormat.parse(fat) ?? 0)
        dismiss()
    }
}
