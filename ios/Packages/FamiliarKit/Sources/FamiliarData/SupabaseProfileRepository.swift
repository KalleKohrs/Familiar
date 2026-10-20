import FamiliarCore
import Foundation
import Supabase

final class SupabaseProfileRepository: ProfileRepository {
    private let client: SupabaseClient
    private static let bucket = "avatars"

    init(client: SupabaseClient) {
        self.client = client
    }

    func myProfile() async throws(FamiliarError) -> Profile {
        let userID = try await client.currentUserID()
        return try await perform {
            try await client.from("profiles").select().eq("id", value: userID).single().execute().value
        }
    }

    func updateDisplayName(_ name: String) async throws(FamiliarError) -> Profile {
        try await updateProfile(UpdateProfileParams(displayName: InputRules.trimmed(name)))
    }

    func uploadAvatar(jpegData: Data) async throws(FamiliarError) -> Profile {
        let userID = try await client.currentUserID()
        let path = Profile.avatarStoragePath(for: userID)
        _ = try await perform {
            try await client.storage.from(Self.bucket).upload(
                path,
                data: jpegData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        }
        return try await updateProfile(UpdateProfileParams(avatarPath: path))
    }

    func removeAvatar() async throws(FamiliarError) -> Profile {
        try await updateProfile(UpdateProfileParams(avatarPath: ""))
    }

    func avatarURL(path: String) async throws(FamiliarError) -> URL {
        try await perform {
            try await client.storage.from(Self.bucket).createSignedURL(path: path, expiresIn: 60 * 60)
        }
    }

    private func updateProfile(_ params: UpdateProfileParams) async throws(FamiliarError) -> Profile {
        try await perform {
            try await client.rpc("update_profile", params: params).execute().value
        }
    }
}

/// Parameter von `update_profile`; `nil` wird nicht gesendet und bedeutet „unverändert“.
private struct UpdateProfileParams: Encodable {
    var displayName: String?
    var avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "p_display_name"
        case avatarPath = "p_avatar_path"
    }
}
