import SwiftUI

/// Checkbox-style picker for available gym equipment with purple theme.
struct EquipmentPickerView: View {
    @Binding var selectedEquipment: [String: Bool]

    private let equipmentOptions = [
        "Dumbbells", "Barbell", "Cables", "Machines",
        "Pull-Up Bar", "Dip Station", "Leg Press",
        "Smith Machine", "Resistance Bands", "Kettlebells"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Equipment")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Select what's available at your gym.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                equipmentGrid
            }
            .padding(24)
        }
    }

    private var equipmentGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(equipmentOptions, id: \.self) { item in
                equipmentToggle(item)
            }
        }
    }

    private func equipmentToggle(_ item: String) -> some View {
        let isSelected = selectedEquipment[item] ?? false
        return Button(action: { toggleEquipment(item) }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                Text(item)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleEquipment(_ item: String) {
        let current = selectedEquipment[item] ?? false
        selectedEquipment[item] = !current
    }
}
