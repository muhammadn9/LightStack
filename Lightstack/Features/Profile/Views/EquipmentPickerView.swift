import SwiftUI

/// Checkbox-style picker for available gym equipment.
/// Used in both OnboardingView (step 3) and Profile editing.
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
                Text("Select what's available at your gym.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(isSelected ? .accent : .secondary)
                Text(item)
                    .font(.subheadline)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func toggleEquipment(_ item: String) {
        let current = selectedEquipment[item] ?? false
        selectedEquipment[item] = !current
    }
}
