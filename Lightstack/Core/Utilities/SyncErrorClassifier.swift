import Foundation
import Supabase

/// How the offline queue should react to a failed remote write.
enum SyncErrorClass: Equatable {
    /// Network / server trouble. Retry later with backoff.
    case transient
    /// Foreign-key violation: the parent row isn't uploaded yet. Retry with backoff.
    case dependency
    /// Unique violation on an insert: the earlier attempt actually landed. Treat as done.
    case alreadyApplied
    /// No valid session. Stop the pass and leave everything untouched.
    case auth
    /// The server will never accept this operation. Move to the dead-letter list.
    case permanent
}

/// Pure error classification for the offline queue (no I/O, no logging of payloads).
enum SyncErrorClassifier {

    /// Insert-type operations for which a duplicate-key error means "already uploaded".
    static let insertTypes: Set<QueuedOperationType> = [
        .insertWorkout, .insertExercises, .insertSet,
        .insertPersonalRecord, .insertMonthPlan, .insertPlannedSessions
    ]

    /// Operations on tables whose row-level-security policy checks the PARENT workout through a
    /// subquery (`exercises`, `sets`). Such a child written before its parent exists is refused with
    /// 42501 / HTTP 403, which here means "parent not uploaded yet", not "not your row".
    static let parentCheckedTypes: Set<QueuedOperationType> = [
        .insertExercises, .insertSet, .renameExercises, .deleteExercise, .deleteExercises, .deleteSet
    ]

    /// The server has no such table yet (a migration that has not been applied): PostgREST `PGRST205`,
    /// or Postgres `42P01`. A bare HTTP 404 is not enough to tell. This is "not ready yet", never "refused for good".
    static func isMissingTable(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError { return isMissingTable(postgresCode: pg.code) }
        return false
    }

    static func isMissingTable(postgresCode code: String?) -> Bool {
        code == "PGRST205" || code == "42P01"
    }

    /// The server lacks a column the client sent (PostgREST `PGRST204`, Postgres `42703`): a migration has not
    /// been applied yet. Retry later; never dead-letter the write.
    static func isMissingColumn(postgresCode code: String?) -> Bool {
        code == "PGRST204" || code == "42703"
    }

    static func classify(_ error: Error, opType: QueuedOperationType) -> SyncErrorClass {
        if error is DecodingError { return .permanent }
        // A table that is not there yet backs off and retries (nothing dropped, no dead letter, and it does not
        // count towards the "offline" streak that stops a pass), so the rest of the queue keeps flowing.
        if isMissingTable(error) { return .dependency }
        if error is URLError { return .transient }
        if error is CancellationError { return .transient }

        if let pg = error as? PostgrestError {
            return classify(postgresCode: pg.code, opType: opType)
        }
        if let http = error as? HTTPError {
            if http.response.statusCode == 403, parentCheckedTypes.contains(opType) { return .dependency }
            return classify(httpStatus: http.response.statusCode)
        }
        if let auth = error as? AuthError {
            switch auth {
            case .sessionMissing, .refreshDiscarded:
                return .auth
            case .api(_, _, _, let response):
                return classify(httpStatus: response.statusCode)
            default:
                return .transient
            }
        }
        return .transient
    }

    static func classify(httpStatus status: Int) -> SyncErrorClass {
        switch status {
        case 401: return .auth
        case 408, 429: return .transient
        case 500...599: return .transient
        case 400...499: return .permanent
        default: return .transient
        }
    }

    static func classify(postgresCode code: String?, opType: QueuedOperationType) -> SyncErrorClass {
        guard let code = code, !code.isEmpty else { return .transient }
        if isMissingTable(postgresCode: code) || isMissingColumn(postgresCode: code) { return .dependency }
        // A food saved with a source the server's CHECK does not know yet ('off' before the barcode migration).
        if code == "23514", opType == .upsertFood { return .dependency }
        switch code {
        case "23503":
            return .dependency
        case "23505":
            return insertTypes.contains(opType) ? .alreadyApplied : .permanent
        case "42501":
            // RLS refusal. For child rows it usually means the parent isn't there yet: retry.
            return parentCheckedTypes.contains(opType) ? .dependency : .permanent
        case "PGRST301", "PGRST302", "PGRST303":
            return .auth                    // JWT expired / invalid / anonymous access disabled
        default:
            break
        }
        // PGRST0xx = connection / pool trouble on the API side.
        if code.hasPrefix("PGRST0") { return .transient }
        // Other PostgREST errors (bad request shape, schema cache, ...) won't fix themselves.
        if code.hasPrefix("PGRST") { return .permanent }
        // SQLSTATE classes: 22 data exception, 23 integrity constraint, 42 syntax/permission.
        if code.hasPrefix("22") || code.hasPrefix("23") || code.hasPrefix("42") { return .permanent }
        // 08 connection, 53 resources, 57 operator intervention, 40 rollback, 55/58 etc.
        return .transient
    }

    /// Short, payload-free code for logs and the dead-letter list.
    static func errorCode(for error: Error) -> String {
        if error is DecodingError { return "decode" }
        if let url = error as? URLError { return "urlerror.\(url.code.rawValue)" }
        if let pg = error as? PostgrestError { return pg.code ?? "postgrest" }
        if let http = error as? HTTPError { return "http.\(http.response.statusCode)" }
        if let auth = error as? AuthError {
            if case .api(_, _, _, let response) = auth { return "auth.http.\(response.statusCode)" }
            return "auth"
        }
        return "unknown"
    }

    /// Short human-readable summary. Never includes row contents.
    static func errorMessage(for error: Error) -> String {
        if error is DecodingError { return "Stored payload could not be decoded" }
        if let url = error as? URLError { return "Network error (\(url.code.rawValue))" }
        if let pg = error as? PostgrestError { return String(pg.message.prefix(120)) }
        if let http = error as? HTTPError { return "HTTP status \(http.response.statusCode)" }
        if error is AuthError { return "Authentication problem" }
        return "Unexpected error"
    }
}
