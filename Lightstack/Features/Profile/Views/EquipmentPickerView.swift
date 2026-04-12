import SwiftUI

/// Checkbox-style picker for available gym equipment with purple theme.
struct EquipmentPickerView: View {
    @Binding var selectedEquipment: [String: Bool]
    @Binding var customEquipment: String

    private let equipmentOptions = [
        "Dumbbells", "Barbell", "Cables", "Machines",
        "Pull-Up Bar", "Dip Station", "Leg Press",
        "Smith Machine", "Resistance Bands", "Kettlebells"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Equipment")
                    .font(AppTheme.playfair(22, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Select what's available at your gym.")
                    .font(AppTheme.caveat(15))
                    .foregroundStyle(AppTheme.textSecondary)

                equipmentGrid

                customEquipmentSection
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
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleEquipment(_ item: String) {
        let current = selectedEquipment[item] ?? false
        selectedEquipment[item] = !current
    }

    private var customEquipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other Equipment")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("List any other equipment you have access to (e.g., TRX, battle ropes, sandbags)")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("Type custom equipment here...", text: $customEquipment, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
        }
    }
}
