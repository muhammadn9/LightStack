import SwiftUI

// MARK: - Note Card

/// Reusable card for workout notes (setup, AI progression, user notes).
/// Hidden automatically when `content` is nil or empty.
struct NoteCardView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String?

    var body: some View {
        if let text = content, !text.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(AppTheme.playfairItalic(16, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Text(text)
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .cardStyle()
        }
    }
}

// MARK: - Ink Divider

/// Hairline horizontal rule — replaces Divider().
struct InkDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.6))
            .frame(height: 0.5)
    }
}

// MARK: - Notebook Binding Strip

/// Formerly a spiral-bound binding strip — now removed visually.
struct NotebookBindingStrip: View {
    var body: some View {
        Color.clear.frame(width: 0)
    }
}

// MARK: - Corner Fold

/// Formerly a corner-fold effect — now removed visually.
struct CornerFold: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - Set Number Circle

/// Circle badge for set numbers. Filled when logged, outlined when pending.
struct SetNumberCircle: View {
    let number: Int
    let isLogged: Bool

    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(isLogged ? AppTheme.accent : Color.clear)
            Circle()
                .stroke(isLogged ? AppTheme.accent : AppTheme.bindingHole, lineWidth: 1.5)
            Text("\(number)")
                .font(AppTheme.plexMono(8, weight: .bold))
                .foregroundStyle(isLogged ? Color.white : AppTheme.textSecondary)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set \(number)")
        .accessibilityValue(isLogged ? "Logged" : "Not logged")
    }
}

// MARK: - PR Stamp

/// Red circular stamp for personal records — rotated slightly for authenticity.
struct PRStamp: View {
    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 31

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.prStamp, lineWidth: 2)
            Text("PR")
                .font(AppTheme.playfairItalic(8, weight: .bold))
                .foregroundStyle(AppTheme.prStamp)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-12))
        .opacity(0.9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personal record")
    }
}

// MARK: - Rest Timer Ring

/// Spinning circle for rest timer countdown.
struct RestTimerRing: View {
    let progress: Double // 0.0 to 1.0

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 45

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.timerTrack, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest timer")
        .accessibilityValue("\(Int(progress * 100)) percent remaining")
    }
}

// MARK: - Ink Fill Bar

/// 5px-height progress bar with no corner radius — ink-style fill.
struct InkFillBar: View {
    let progress: Double // 0.0 to 1.0

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 5)
            .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 1))
            .background(alignment: .leading) {
                // Scaling from the leading edge gives an exact proportional fill
                // without reading geometry: the rectangle lays out at the bar's
                // full width, then shrinks to `clamped` of it. `layoutPriority`
                // cannot do this — it grants space by rank, not by fraction.
                Rectangle()
                    .fill(AppTheme.accent)
                    .scaleEffect(x: clamped, anchor: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

// MARK: - Notebook Page Modifier

/// Pass-through wrapper (binding strip and corner fold removed).
struct NotebookPageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func notebookPage() -> some View {
        modifier(NotebookPageModifier())
    }
}
