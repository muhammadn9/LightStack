import SwiftUI

/// Drag-to-reorder list of the workout's exercises. A superset is one row listing
/// its members, so it always moves as a whole. Done hands back the new unit order.
struct ReorderExercisesSheet: View {
    let exercises: [Exercise]
    let onDone: ([[UUID]]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var units: [[UUID]]

    init(exercises: [Exercise], onDone: @escaping ([[UUID]]) -> Void) {
        self.exercises = exercises
        self.onDone = onDone
        _units = State(initialValue: ExerciseOrdering.units(from: exercises))
    }

    private func name(of id: UUID) -> String {
        exercises.first { $0.id == id }?.name ?? ""
    }

    private func rowKey(_ unit: [UUID]) -> String {
        unit.first.map(name(of:)) ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(units, id: \.self) { unit in
                    row(for: unit)
                        .listRowBackground(AppTheme.surface)
                }
                .onMove { source, destination in
                    units.move(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("reorderCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(units)
                        dismiss()
                    }
                    .accessibilityIdentifier("reorderDoneButton")
                }
            }
        }
        .accessibilityIdentifier("reorderSheet")
    }

    private func row(for unit: [UUID]) -> some View {
        let key = rowKey(unit)
        let index = units.firstIndex(of: unit) ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if unit.count > 1 {
                    Text("Superset")
                        .font(AppTheme.plexMono(10, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                ForEach(unit, id: \.self) { id in
                    Text(name(of: id))
                        .font(AppTheme.caveat(18))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            Spacer()
            // Buttons double as an accessible alternative to dragging.
            Button { move(unit, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel("Move \(key) up")
            .accessibilityIdentifier("reorderUp.\(key)")
            Button { move(unit, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index >= units.count - 1)
            .accessibilityLabel("Move \(key) down")
            .accessibilityIdentifier("reorderDown.\(key)")
        }
        .foregroundStyle(AppTheme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reorderRow.\(key)")
    }

    private func move(_ unit: [UUID], by offset: Int) {
        guard let index = units.firstIndex(of: unit) else { return }
        let target = index + offset
        guard units.indices.contains(target) else { return }
        withAnimation { units.swapAt(index, target) }
    }
}
