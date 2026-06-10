import SwiftUI

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

/// 16x16 circle badge for set numbers. Filled when logged, outlined when pending.
struct SetNumberCircle: View {
    let number: Int
    let isLogged: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isLogged ? AppTheme.accent : Color.clear)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(isLogged ? AppTheme.accent : AppTheme.bindingHole, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Text("\(number)")
                .font(AppTheme.plexMono(8, weight: .bold))
                .foregroundStyle(isLogged ? Color.white : Color.secondary)
        }
    }
}

// MARK: - PR Stamp

/// 28x28 red circular stamp for personal records — rotated slightly for authenticity.
struct PRStamp: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.prStamp, lineWidth: 2)
                .frame(width: 31, height: 31)
            Text("PR")
                .font(AppTheme.playfairItalic(8, weight: .bold))
                .foregroundStyle(AppTheme.prStamp)
        }
        .rotationEffect(.degrees(-12))
        .opacity(0.9)
    }
}

// MARK: - Rest Timer Ring

/// 40x40 spinning circle for rest timer countdown.
struct RestTimerRing: View {
    let progress: Double // 0.0 to 1.0

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(AppTheme.timerTrack, lineWidth: 3.5)
                .frame(width: 45, height: 45)
            // Active arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
        }
    }
}

// MARK: - Ink Fill Bar

/// 5px-height progress bar with no corner radius — ink-style fill.
struct InkFillBar: View {
    let progress: Double // 0.0 to 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 5)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: 5)
            }
        }
        .frame(height: 5)
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
