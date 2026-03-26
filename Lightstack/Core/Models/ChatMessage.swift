import Foundation

/// In-memory only — not persisted to Core Data or Supabase.
/// Represents a single message in the AI coach chat.
struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum ChatRole {
    case user
    case coach
}
