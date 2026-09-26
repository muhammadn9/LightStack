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

// MARK: - Expandable Card

/// A card that expands to reveal detail, with spring motion and haptics.
///
/// Motion is physics-based so a rapid second tap retargets the spring rather
/// than restarting it. Both the animation and the haptic defer to the user's
/// accessibility settings.
struct ExpandableCard<Header: View, Detail: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var header: Header
    @ViewBuilder var detail: Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppMotion.cardExpand) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    header
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapses details" : "Expands details")

            if isExpanded {
                detail
                    .padding(.top, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal:   .opacity
                        )
                    )
            }
        }
        .lsCard()
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
        .animation(reduceMotion ? nil : AppMotion.cardExpand, value: isExpanded)
    }
}

// MARK: - Press Feedback

/// Scales and dims a card slightly while pressed. Skips the scale under
/// Reduce Motion, keeping only the opacity change.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(pressed: configuration.isPressed))
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(AppMotion.press, value: configuration.isPressed)
    }

    private func scale(pressed: Bool) -> CGFloat {
        guard pressed, !reduceMotion else { return 1.0 }
        return 0.98
    }
}
