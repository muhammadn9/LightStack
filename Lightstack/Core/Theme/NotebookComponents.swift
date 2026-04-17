import SwiftUI

// MARK: - Ink Divider

/// Gradient horizontal rule that fades at edges — replaces Divider().
struct InkDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: AppTheme.border, location: 0.2),
                        .init(color: AppTheme.border, location: 0.8),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}

// MARK: - Notebook Binding Strip

/// 18px-wide left-edge strip with spiral holes, mimicking a spiral-bound notebook.
struct NotebookBindingStrip: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.bindingStrip)
                .frame(width: 18)
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    if i > 0 { Spacer() }
                    Circle()
                        .fill(AppTheme.bindingHole)
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .frame(width: 18)
    }
}

// MARK: - Corner Fold

/// 20x20 triangle fold effect at bottom-right of a page/card.
struct CornerFold: View {
    var body: some View {
        Triangle()
            .fill(
                LinearGradient(
                    colors: [AppTheme.cornerFold, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 20, height: 20)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
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
                .foregroundStyle(
                    isLogged
                        ? Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1)
                        : AppTheme.textSecondary
                )
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
                .frame(width: 32, height: 32)
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

/// Wraps content with a binding strip on the leading edge and corner fold at bottom-right.
struct NotebookPageModifier: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            NotebookBindingStrip()
            content
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            CornerFold()
                .padding(4)
        }
    }
}

extension View {
    func notebookPage() -> some View {
        modifier(NotebookPageModifier())
    }
}
