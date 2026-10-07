import SwiftUI

/// "Equipment Worked This Week" hero: N of 7 kinds, icons glowing by set count, total sets ring.
struct EquipmentWeekCard: View {
    let usage: [EquipmentKind: Int]

    private var usedCount: Int { EquipmentKind.allCases.filter { (usage[$0] ?? 0) > 0 }.count }
    private var totalSets: Int { usage.values.reduce(0, +) }

    private func intensity(_ sets: Int) -> Double {
        sets == 0 ? 0 : min(1, 0.35 + Double(sets) / 18)
    }

    var body: some View {
        ProgressCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(usedCount) of 7")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityIdentifier("equipment.usedCount")
                        Text("\(Int((Double(usedCount) / 7 * 100).rounded()))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text("Equipment Worked This Week")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(EquipmentKind.allCases) { kind in
                        let sets = usage[kind] ?? 0
                        VStack(spacing: 5) {
                            EquipmentIcon(kind: kind, intensity: intensity(sets))
                                .padding(.horizontal, 6)
                            Text(kind.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(sets > 0 ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(sets > 0 ? "\(sets) sets" : "not yet")
                                .font(.caption2)
                                .foregroundStyle(sets > 0 ? AppTheme.accent : ProgressStyle.dim)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(kind.name), \(sets > 0 ? "\(sets) sets" : "not yet")")
                        .accessibilityIdentifier("equipment.\(kind.name)")
                    }
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(AppTheme.surfaceElevated, lineWidth: 5)
                            Circle().trim(from: 0, to: Double(usedCount) / 7)
                                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(totalSets)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 44, height: 44)
                        .frame(maxHeight: 50)
                        Text("Total sets")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Total sets \(totalSets)")
                    .accessibilityIdentifier("equipment.totalSets")
                }
            }
        }
    }
}
