import FamiliarCore
import FamiliarDesign
import ImageIO
import Observation
import SwiftUI
import UIKit

/// Bereitet ein gewähltes Foto als Profilbild auf.
enum AvatarImageProcessor {
    /// Verkleinert auf höchstens `maxPixelSize` (längste Seite), richtet nach EXIF aus und kodiert
    /// als JPEG. Metadaten wie Aufnahmeort werden dabei nicht übernommen.
    static func jpegData(from data: Data, maxPixelSize: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}

/// Lädt Profilbilder über kurzlebige signierte URLs und hält sie im Speicher.
/// Schlüssel: Pfad + `updated_at` des Profils, damit ein neues Bild (gleicher Pfad) neu geladen wird.
@Observable
final class AvatarImageStore {
    private var images: [String: Image] = [:]
    private var loading: Set<String> = []
    private let profiles: any ProfileRepository

    init(profiles: any ProfileRepository) {
        self.profiles = profiles
    }

    static func cacheKey(for profile: Profile) -> String? {
        profile.avatarPath.map { "\($0)|\(profile.updatedAt.timeIntervalSince1970)" }
    }

    func image(for profile: Profile?) -> Image? {
        guard let profile, let key = Self.cacheKey(for: profile) else { return nil }
        return images[key]
    }

    func load(_ profile: Profile) async {
        guard let path = profile.avatarPath, let key = Self.cacheKey(for: profile),
              images[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let url = try await profiles.avatarURL(path: path)
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                images[key] = Image(uiImage: image)
            }
        } catch {
            // Ohne Bild zeigt AvatarView die Initialen.
        }
    }
}

/// Profilbild einer Person; Initialen, solange kein Bild vorhanden oder geladen ist.
struct ProfileAvatar: View {
    @Environment(AvatarImageStore.self) private var avatars
    let profile: Profile?
    let name: String
    var diameter: CGFloat = 32
    var completion: AssigneeCompletion? = nil

    var body: some View {
        AvatarView(name: name, image: avatars.image(for: profile), diameter: diameter, completion: completion)
            .task(id: profile.flatMap(AvatarImageStore.cacheKey)) {
                if let profile { await avatars.load(profile) }
            }
    }
}
