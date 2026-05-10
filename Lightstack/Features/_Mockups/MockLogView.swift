import SwiftUI

enum LogTab: String, CaseIterable, Identifiable {
    case history = "History"
    case prs = "PRs"
    case insights = "Insights"
    var id: String { rawValue }
}

struct MockLogView: View {
    @State private var selectedTab: LogTab = .history

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: ModernTheme.spacingS), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ModernTheme.spacingL) {
                    statsRow
                    tabPicker
                    tabContent
                }
                .padding(.horizontal, ModernTheme.spacingM)
                .padding(.bottom, ModernTheme.spacingL)
            }
            .modernScreenBackground()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .foregroundStyle(ModernTheme.accent)
                }
            }
        }
    }

    private var statsRow: some View {
        LazyVGrid(columns: gridColumns, spacing: ModernTheme.spacingS) {
            ModernStatTile(
                value: "\(MockData.userStreak)",
                label: "Day streak",
                systemImage: "flame.fill"
            )
            ModernStatTile(
                value: "\(MockData.userTotalSessions)",
                label: "Sessions",
                systemImage: "checkmark.seal.fill"
            )
            ModernStatTile(
                value: String(format: "%.1fM", MockData.userTotalVolumeLbs / 1_000_000.0),
                label: "Lbs lifted",
                systemImage: "scalemass.fill"
            )
        }
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(LogTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .history:
            historyTab
        case .prs:
            prsTab
        case .insights:
            insightsTab
        }
    }

    private var historyTab: some View {
        VStack(spacing: ModernTheme.spacingS) {
            ForEach(MockData.history) { entry in
                Button {
                } label: {
                    HStack(spacing: ModernTheme.spacingM) {
                        ZStack {
                            Circle()
                                .fill(ModernTheme.accent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(ModernTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.workoutType)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(relativeDate(entry.date))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack(spacing: ModernTheme.spacingS) {
                                Label("\(entry.durationMinutes) min", systemImage: "clock")
                                Label(shortVolume(entry.totalVolumeLbs), systemImage: "scalemass")
                                Label("\(entry.exerciseCount) exercises", systemImage: "list.bullet")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        if entry.prCount > 0 {
                            ModernChip(
                                label: "\(entry.prCount) PR",
                                icon: "trophy.fill",
                                tint: .orange
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .modernCardFilled()
            }
        }
    }

    private var prsTab: some View {
        VStack(spacing: ModernTheme.spacingS) {
            ForEach(MockData.prs) { pr in
                HStack(spacing: ModernTheme.spacingM) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pr.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(String(format: "%.0f", pr.weightLbs)) lbs × \(pr.reps)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(relativeDate(pr.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .modernCardFilled()
            }
        }
    }

    private var insightsTab: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingM) {
            Text("Volume by muscle group")
                .font(.headline)

            let maxVolume = MockData.muscleVolume.map(\.volume).max() ?? 1

            GeometryReader { geo in
                let availableWidth = geo.size.width

                VStack(spacing: ModernTheme.spacingS) {
                    ForEach(MockData.muscleVolume, id: \.muscle) { item in
                        HStack(spacing: ModernTheme.spacingS) {
                            Text(item.muscle)
                                .font(.subheadline)
                                .frame(width: 80, alignment: .leading)

                            let barWidth = availableWidth * CGFloat(item.volume / maxVolume)
                            let totalBarWidth = availableWidth - 80 - 60 - ModernTheme.spacingS * 2

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ModernTheme.accent.opacity(0.15))
                                    .frame(width: totalBarWidth, height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ModernTheme.accent)
                                    .frame(width: min(barWidth, totalBarWidth), height: 8)
                            }

                            Spacer(minLength: 0)

                            Text(shortVolumeK(item.volume))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(MockData.muscleVolume.count) * (20 + ModernTheme.spacingS))
        }
        .modernCard()
    }
}

private func relativeDate(_ date: Date) -> String {
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
    switch days {
    case 0: return "Today"
    case 1: return "Yesterday"
    case 2...6: return "\(days) days ago"
    default:
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

private func shortVolumeK(_ value: Double) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", value / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.1fK", value / 1_000)
    } else {
        return String(format: "%.0f", value)
    }
}

private func shortVolume(_ value: Double) -> String {
    shortVolumeK(value)
}

#Preview("Light") {
    MockLogView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MockLogView()
        .preferredColorScheme(.dark)
}
