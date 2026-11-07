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

    /// Restores a saved message with its original id and time.
    init(id: UUID, role: ChatRole, content: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum ChatRole {
    case user
    case coach
}
