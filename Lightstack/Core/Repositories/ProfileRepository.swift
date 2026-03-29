import Foundation

/// Coordinates local + remote profile data access.
final class ProfileRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let offlineQueueManager: OfflineQueueManager

    init(
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
        self.offlineQueueManager = offlineQueueManager
    }

    /// Read profile from Core Data instantly, then background-fetch from Supabase.
    func loadProfile(userId: UUID) -> UserProfile? {
        let local = fetchProfileSync(userId: userId)
        Task {
            try? await syncProfileFromRemote(userId: userId)
        }
        return local
    }

    /// Synchronous read for CoachContextBuilder and other immediate needs.
    func fetchProfileSync(userId: UUID) -> UserProfile? {
        guard let cdEntity = localStorage.fetchProfile(userId: userId) else {
            return nil
        }
        return UserProfile(from: cdEntity)
    }

    /// Write profile to Core Data first, then attempt Supabase upsert.
    func saveProfile(_ profile: UserProfile) {
        localStorage.saveProfile(profile)
        Task {
            do {
                try await supabaseService.upsertProfile(profile)
            } catch {
                offlineQueueManager.enqueue(.upsertProfile, payload: profile)
            }
        }
    }

    // MARK: - Private

    private func syncProfileFromRemote(userId: UUID) async throws {
        guard let remote = try await supabaseService.fetchProfile(userId: userId) else {
            return
        }
        localStorage.saveProfile(remote)
    }
}
