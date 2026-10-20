import Foundation

/// Einladung in eine Familie (`public.family_invites`).
public struct FamilyInvite: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let familyID: UUID
    public let code: String
    public var expiresAt: Date
    public var revokedAt: Date?
    public var useCount: Int

    public init(id: UUID, familyID: UUID, code: String, expiresAt: Date, revokedAt: Date? = nil, useCount: Int = 0) {
        self.id = id
        self.familyID = familyID
        self.code = code
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.useCount = useCount
    }

    enum CodingKeys: String, CodingKey {
        case id, code
        case familyID = "family_id"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case useCount = "use_count"
    }

    public func isActive(at date: Date = .now) -> Bool {
        revokedAt == nil && expiresAt > date
    }
}

/// Ergebnis von `join_family`. Ungültige Codes sind bewusst kein Fehler (Rate-Limit, siehe Datenmodell).
public struct JoinFamilyResult: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case joined
        case alreadyMember = "already_member"
        case invalidFormat = "invalid_format"
        case invalidCode = "invalid_code"
        case expired
        case revoked
        case rateLimited = "rate_limited"
    }

    public let status: Status
    public let familyID: UUID?
    public let retryAfterSeconds: Int?
    /// Deutsche Meldung vom Server.
    public let message: String

    public init(status: Status, familyID: UUID? = nil, retryAfterSeconds: Int? = nil, message: String) {
        self.status = status
        self.familyID = familyID
        self.retryAfterSeconds = retryAfterSeconds
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case status, message
        case familyID = "family_id"
        case retryAfterSeconds = "retry_after_seconds"
    }

    public var isSuccess: Bool { status == .joined || status == .alreadyMember }
}

/// Ergebnis von `leave_family`.
public enum LeaveFamilyResult: String, Codable, Hashable, Sendable {
    case left
    case familyDeleted = "family_deleted"
}
