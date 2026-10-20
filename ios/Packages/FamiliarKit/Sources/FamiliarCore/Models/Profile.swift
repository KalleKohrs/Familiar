import Foundation

/// Profil einer Person (`public.profiles`). Wird beim Registrieren automatisch angelegt.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    /// Pfad im Storage-Bucket `avatars` (`{user_id}/avatar.jpg`) oder `nil`.
    public var avatarPath: String?
    public var updatedAt: Date

    public init(id: UUID, displayName: String, avatarPath: String? = nil, updatedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case updatedAt = "updated_at"
    }

    /// Fester Pfad des Profilbilds; ein neues Bild überschreibt das alte (Migration 0006).
    public static func avatarStoragePath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/avatar.jpg"
    }
}
