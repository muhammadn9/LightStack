import Foundation

/// Queues writes when the device is offline.
/// Flushes pending records to Supabase on reconnect.
/// Uses local_id (device UUID) to prevent duplicate inserts on retry.
final class OfflineQueueManager {
    // TODO: Phase 4 — Implement offline write queue and flush logic
}
