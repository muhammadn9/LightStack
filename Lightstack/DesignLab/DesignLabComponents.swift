#if DEBUG
import SwiftUI

// MARK: - Card

struct DLCard<Content: View>: View {
    @Environment(\.dlTheme) private var t
    var margin = false
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        let leading: CGFloat = (margin && t.isNotebook) ? 36 : padding
        content()
            .padding(.leading, leading)
            .padding(.trailing, padding)
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(t.card)
                    if t.isNotebook {
                        Canvas { ctx, size in
                            var y: CGFloat = 34
                            while y < size.height - 6 {
                                var p = Path()
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: size.width, y: y))
                                ctx.stroke(p, with: .color(Color(hex: 0xA9C4E0).opacity(0.06)), lineWidth: 1)
                                y += 26
                            }
                            if margin {
                                var m = Path()
                                m.move(to: CGPoint(x: 26, y: 0))
                                m.addLine(to: CGPoint(x: 26, y: size.height))
                                ctx.stroke(m, with: .color(t.stamp.opacity(0.35)), lineWidth: 1)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(t.hairline, lineWidth: 1))
            }
    }
}

// MARK: - Buttons & chips

struct DLPillButton: View {
    @Environment(\.dlTheme) private var t
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Image(systemName: icon).font(.system(size: 18, weight: .bold)) }
            Text(title).font(t.isNotebook ? t.heading(20) : t.label(19, weight: .bold))
        }
        .foregroundStyle(t.onAccent)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(t.accent, in: Capsule())
        .shadow(color: t.accent.opacity(0.3), radius: 14, y: 4)
    }
}

struct DLChip: View {
    @Environment(\.dlTheme) private var t
    let text: String
    var icon: String?
    var highlighted = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
            Text(text).font(t.label(13))
        }
        .foregroundStyle(highlighted ? t.onAccent : t.subtext)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(highlighted ? t.accent : t.field, in: Capsule())
    }
}

struct DLIconButton: View {
    @Environment(\.dlTheme) private var t
    let symbol: String
    var prominent = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(prominent ? t.onAccent : t.text)
            .frame(width: 48, height: 48)
            .background(prominent ? t.accent : t.field, in: Circle())
    }
}

/// Red ink stamp, same look as the real app's PRStamp but sized up for the mock.
struct DLPRBadge: View {
    @Environment(\.dlTheme) private var t

    var body: some View {
        if t.isNotebook {
            PRStamp()
                .scaleEffect(1.15)
                .frame(width: 38, height: 38)
        } else {
            Text("PR")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(t.onAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(t.accent, in: Capsule())
        }
    }
}

// MARK: - Tab bar

struct DLTabBar: View {
    @Environment(\.dlTheme) private var t
    let selected: Int
    private let items: [(String, String)] = [
        ("Today", "figure.strengthtraining.traditional"),
        ("History", "clock.arrow.circlepath"),
        ("Progress", "chart.line.uptrend.xyaxis"),
        ("Profile", "person.crop.circle")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 4) {
                    Image(systemName: item.1)
                        .font(.system(size: 22, weight: .regular))
                        .frame(height: 26)
                    Text(item.0).font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(index == selected ? t.accent : t.subtext)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 4)
        .background(t.barBg.opacity(0.97).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(t.hairline).frame(height: 1) }
    }
}

// MARK: - Week strip

struct DLWeekStrip: View {
    @Environment(\.dlTheme) private var t
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]
    private let numbers = [5, 6, 7, 8, 9, 10, 11]
    private let trained: Set<Int> = [0, 1, 2]
    private let todayIndex = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let isToday = i == todayIndex
                VStack(spacing: 7) {
                    Text(letters[i])
                        .font(t.isNotebook ? t.note(12) : t.label(12, weight: .medium))
                        .foregroundStyle(isToday ? t.text : t.subtext)
                    Text("\(numbers[i])")
                        .font(t.isNotebook ? t.number(17) : t.number(17))
                        .foregroundStyle(isToday ? t.onAccent : t.text)
                        .frame(width: 40, height: 40)
                        .background(isToday ? t.accent : t.card, in: Circle())
                        .overlay {
                            if t.isNotebook && !isToday {
                                Circle().stroke(t.hairline, lineWidth: 1)
                            }
                        }
                    Circle()
                        .fill(trained.contains(i) ? t.accent : .clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Heatmap

struct DLHeatmap: View {
    @Environment(\.dlTheme) private var t
    private let weeks = 13

    private func level(week: Int, day: Int) -> Int {
        // Last week is partial: today is index 3, later days are in the future.
        if week == weeks - 1 && day > 3 { return -1 }
        let h = (week * 7 + day) * 2654435761 % 1000
        let bias = week > 6 ? 0 : 1
        let v = h % 11
        if v < 3 + bias * 2 { return 0 }
        if v < 6 + bias { return 1 }
        if v < 8 { return 2 }
        if v < 10 { return 3 }
        return 4
    }

    private func color(_ lvl: Int) -> Color {
        switch lvl {
        case -1: return .clear
        case 0: return Color.white.opacity(0.07)
        default: return t.accent.opacity([0, 0.3, 0.5, 0.75, 1.0][lvl])
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let lvl = level(week: w, day: d)
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(color(lvl))
                            .overlay {
                                if lvl == -1 {
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .stroke(t.hairline, lineWidth: 1)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
}

// MARK: - Section title

struct DLSectionTitle: View {
    @Environment(\.dlTheme) private var t
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).font(t.heading(19)).foregroundStyle(t.text)
            Spacer()
            if let trailing {
                Text(trailing).font(t.note(13)).foregroundStyle(t.subtext)
            }
        }
    }
}
#endif
