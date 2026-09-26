import SwiftUI

// MARK: - Protocol

/// A card's visual treatment, resolved from the environment.
///
/// Mirrors SwiftUI's own `ButtonStyle` pattern: apply `.lsCardStyle(_:)` to any
/// ancestor and every `.lsCard()` beneath it adopts that treatment.
protocol LSCardStyle {
    /// Wraps the card's content in this style's chrome.
    func makeBody(content: AnyView) -> AnyView
}

// MARK: - Concrete Styles

/// Translucent material card with a hairline border.
struct PlainCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

/// Material card with a leading accent strip.
struct AccentedCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.8))
                        .frame(width: 3)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

/// Material card lifted with a soft shadow.
struct ElevatedCardStyle: LSCardStyle {
    func makeBody(content: AnyView) -> AnyView {
        AnyView(
            content
                .padding(AppTheme.cardPadding)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
    }
}

// MARK: - Environment

private struct LSCardStyleKey: EnvironmentKey {
    static let defaultValue: any LSCardStyle = PlainCardStyle()
}

extension EnvironmentValues {
    var lsCardStyle: any LSCardStyle {
        get { self[LSCardStyleKey.self] }
        set { self[LSCardStyleKey.self] = newValue }
    }
}

// MARK: - View API

private struct LSCardBody: ViewModifier {
    @Environment(\.lsCardStyle) private var inheritedStyle

    /// Names the style directly instead of inheriting it.
    ///
    /// `.lsCardStyle(x).lsCard()` cannot work: `environment(_:_:)` pushes its
    /// value *down* to the view it wraps, but `.lsCard()` is applied on the
    /// outside of that, so it reads the ambient value and never sees `x`. Call
    /// sites that already know their style pass it here.
    let explicitStyle: (any LSCardStyle)?

    func body(content: Content) -> some View {
        (explicitStyle ?? inheritedStyle).makeBody(content: AnyView(content))
    }
}

extension View {
    /// Applies the card treatment set by the nearest enclosing `.lsCardStyle(_:)`.
    func lsCard() -> some View {
        modifier(LSCardBody(explicitStyle: nil))
    }

    /// Applies `style` to this card, ignoring anything set in the environment.
    func lsCard(_ style: any LSCardStyle) -> some View {
        modifier(LSCardBody(explicitStyle: style))
    }

    /// Sets the card treatment for this view's descendants.
    func lsCardStyle(_ style: any LSCardStyle) -> some View {
        environment(\.lsCardStyle, style)
    }
}
