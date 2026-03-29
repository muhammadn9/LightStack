import SwiftUI

/// Reusable message bubble component for the coach chat.
/// Used in CoachChatView and PlanBuilderChatView.
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(AppTheme.accentGradient)
                            : AnyShapeStyle(AppTheme.surface)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if message.role == .coach { Spacer(minLength: 48) }
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.timestamp)
    }
}
