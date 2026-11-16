import SwiftUI
import Charts

/// Log a weigh-in (new, any past day) or edit an existing one's weight.
struct WeightSheet: View {
    @ObservedObject var viewModel: NutritionViewModel
    var editing: WeighIn?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var date: Date

    init(viewModel: NutritionViewModel, editing: WeighIn? = nil) {
        self.viewModel = viewModel
        self.editing = editing
        let unit = viewModel.bodyWeightUnit
        let lbs = editing?.weightLbs ?? viewModel.latestWeighIn()?.weightLbs
        _text = State(initialValue: lbs.map { NutritionFormat.field(unit.fromLbs($0)) } ?? "")
        _date = State(initialValue: editing?.date ?? Date())
    }

    private var unit: BodyWeightUnit { viewModel.bodyWeightUnit }

    /// A positive, plausible weight in the user's unit.
    private var value: Double? {
        guard let v = NutritionFormat.parse(text), v > 0, v <= (unit == .kg ? 700 : 1500) else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Weight", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("weight.value")
                    Text(unit.label).foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if editing == nil {
                    HStack {
                        Text("Date").foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityIdentifier("weight.date")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text((editing?.date ?? date).formatted(.dateTime.weekday(.wide).month().day().year()))
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }

                Button(action: save) {
                    Text("Save").font(.headline).foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(value == nil ? AppTheme.textSecondary.opacity(0.4) : AppTheme.accent,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(value == nil)
                .accessibilityIdentifier("weight.save")
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(editing == nil ? "Log weight" : "Edit weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .keyboardDoneButton()
        .accessibilityIdentifier("weight.sheet")
    }

    private func save() {
        guard let value else { return }
        if let editing {
            viewModel.updateWeighIn(editing, value: value)
        } else {
            viewModel.logWeight(value, on: date)
        }
        dismiss()
    }
}

/// Weight history: a line chart of the last 90 days and every weigh-in, newest first.
struct WeightHistoryView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var series: [WeightPoint] = []
    @State private var rows: [WeighIn] = []
    @State private var sheet: HistorySheet?
    @State private var pendingDelete: WeighIn?

    private enum HistorySheet: Identifiable {
        case log
        case edit(WeighIn)
        var id: String {
            switch self {
            case .log: return "log"
            case .edit(let w): return w.id.uuidString
            }
        }
    }

    private var unit: BodyWeightUnit { viewModel.bodyWeightUnit }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                chartCard
                listCard
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .log } label: { Label("Log weight", systemImage: "plus") }
                    .accessibilityIdentifier("weight.history.log")
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .log: WeightSheet(viewModel: viewModel).presentationDetents([.medium, .large])
            case .edit(let weighIn): WeightSheet(viewModel: viewModel, editing: weighIn).presentationDetents([.medium, .large])
            }
        }
        .alert("Delete this weigh-in?", isPresented: Binding(get: { pendingDelete != nil },
                                                            set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { viewModel.deleteWeighIn(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.weightHistory")
        .onAppear(perform: refresh)
        .onChange(of: viewModel.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        let today = Date().startOfDay
        series = viewModel.dashboard(for: today)?.weightSeries ?? []
        rows = viewModel.weighIns(in: Date.distantPast...Date()).sorted { $0.date > $1.date }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 90 days").font(.headline).foregroundStyle(AppTheme.textPrimary)
            if series.count < 2 {
                Text("Log at least two weigh-ins to see a trend.")
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(series) { point in
                    LineMark(x: .value("Date", point.date, unit: .day), y: .value("Weight", point.value))
                        .foregroundStyle(AppTheme.accent)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date, unit: .day), y: .value("Weight", point.value))
                        .foregroundStyle(AppTheme.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                } }
                .frame(height: 190)
                .accessibilityIdentifier("weight.chart")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No weigh-ins yet").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityIdentifier("weight.empty")
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let dayId = JournalFormat.dayId(row.date)
                if index > 0 { Divider().padding(.leading, 16) }
                HStack {
                    Text(row.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("\(NutritionFormat.amount(unit.fromLbs(row.weightLbs))) \(unit.label)")
                        .font(.body.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(AppTheme.surface)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .accessibilityValue("\(NutritionFormat.amount(unit.fromLbs(row.weightLbs))) \(unit.label)")
                .accessibilityIdentifier("weight.row.\(dayId)")
                .swipeToDelete(id: "weight.delete.\(dayId)", onTap: { sheet = .edit(row) }, onDelete: { pendingDelete = row })
            }
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}
