import Foundation

/// Coordinates lifecycle of reader sessions.
/// Main-actor confined dictionary keeps bookkeeping simple
/// while individual sessions can perform async work internally.
@MainActor
final class ReadingSessionManager {
    static let shared = ReadingSessionManager()

    private var sessions: [UUID: ReadingSession] = [:]

    private init() {}

    /// Start and register a new session for the provided URL.
    @discardableResult
    func startSession(for url: URL) -> ReadingSession {
        let session = ReadingSession(sourceURL: url)
        sessions[session.id] = session
        return session
    }

    /// Retrieve a session by identifier.
    func session(withID id: UUID) -> ReadingSession? {
        sessions[id]
    }

    /// Gracefully terminate and remove a session.
    func closeSession(withID id: UUID) {
        guard let session = sessions[id] else { return }
        Task { await session.prepareForClose() }
        sessions.removeValue(forKey: id)
    }

    /// Close all active sessions – typically on app termination.
    func closeAllSessions() {
        let snapshot = Array(sessions.values)
        snapshot.forEach { session in
            Task { await session.prepareForClose() }
        }
        sessions.removeAll()
    }
}
