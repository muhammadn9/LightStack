import SwiftUI
import UIKit

/// Shows a floating "Done" pill above the keyboard while it is visible.
/// Replaces `ToolbarItemGroup(placement: .keyboard)`, which is unreliable
/// inside nested TabView + NavigationStack hierarchies and absent on number pads.
/// Apply once per presentation root (app root, plus each sheet/fullScreenCover).
private struct KeyboardDoneButtonModifier: ViewModifier {
    @State private var isKeyboardVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if isKeyboardVisible {
                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Text("Done")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(AppTheme.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss keyboard")
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                setVisible(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                setVisible(false)
            }
    }

    private func setVisible(_ visible: Bool) {
        if reduceMotion {
            isKeyboardVisible = visible
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = visible }
        }
    }
}

extension View {
    /// Adds a floating Done pill above the keyboard while it is showing.
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButtonModifier())
    }
}
