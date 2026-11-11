import FamiliarCore
import FamiliarDesign
import ImageIO
import Observation
import SwiftUI
import UIKit

/// Bereitet gewählte oder aufgenommene Fotos auf.
enum ImageProcessor {
    /// Verkleinert auf höchstens `maxPixelSize` (längste Seite), richtet nach EXIF aus und kodiert
    /// als JPEG. Metadaten wie der Aufnahmeort werden dabei nicht übernommen.
    static func jpeg(from data: Data, maxPixelSize: Int, quality: CGFloat = 0.82) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: quality) else { return nil }
        return (jpeg, image.width, image.height)
    }

    /// Profilbild: 512 px.
    static func avatarJPEG(from data: Data) -> Data? {
        jpeg(from: data, maxPixelSize: 512)?.data
    }

    /// Aufgabenbild: 2048 px für die Großansicht, 480 px als Miniatur für Liste und Editor.
    static func taskImage(from data: Data) -> PreparedImage? {
        guard let full = jpeg(from: data, maxPixelSize: 2048, quality: 0.8),
              let thumbnail = jpeg(from: data, maxPixelSize: 480, quality: 0.75) else { return nil }
        return PreparedImage(jpegData: full.data, thumbnailData: thumbnail.data, width: full.width, height: full.height)
    }
}

/// Lädt Bilder über kurzlebige signierte URLs und hält sie im Speicher.
/// Der Cache-Schlüssel ist der Pfad (Plan, Abschnitt 3), nie die URL.
@Observable
final class RemoteImageCache {
    private var images: [String: Image] = [:]
    private var loading: Set<String> = []
    private let resolveURL: @Sendable (String) async throws(FamiliarError) -> URL

    init(resolveURL: @escaping @Sendable (String) async throws(FamiliarError) -> URL) {
        self.resolveURL = resolveURL
    }

    func image(forKey key: String) -> Image? {
        images[key]
    }

    /// `key` darf mehr als den Pfad enthalten (z. B. Pfad + Änderungszeit), `path` ist der Speicherort.
    func load(key: String, path: String) async {
        guard images[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let url = try await resolveURL(path)
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                images[key] = Image(uiImage: image)
            }
        } catch {
            // Ohne Bild bleibt der Platzhalter sichtbar.
        }
    }

    /// Gerade hochgeladene Bilder sofort anzeigen, ohne sie erneut zu laden.
    func insert(_ data: Data, forKey key: String) {
        if let image = UIImage(data: data) {
            images[key] = Image(uiImage: image)
        }
    }
}

/// Profilbilder: Schlüssel = Pfad + `updated_at`, weil ein neues Bild denselben Pfad hat.
@Observable
final class AvatarImageStore {
    private let cache: RemoteImageCache

    init(profiles: any ProfileRepository) {
        cache = RemoteImageCache { path async throws(FamiliarError) in try await profiles.avatarURL(path: path) }
    }

    static func cacheKey(for profile: Profile) -> String? {
        profile.avatarPath.map { "\($0)|\(profile.updatedAt.timeIntervalSince1970)" }
    }

    func image(for profile: Profile?) -> Image? {
        guard let profile, let key = Self.cacheKey(for: profile) else { return nil }
        return cache.image(forKey: key)
    }

    func load(_ profile: Profile) async {
        guard let path = profile.avatarPath, let key = Self.cacheKey(for: profile) else { return }
        await cache.load(key: key, path: path)
    }
}

/// Aufgabenbilder: Pfade sind eindeutig und ändern sich nie, daher Schlüssel = Pfad.
@Observable
final class TaskImageStore {
    private let cache: RemoteImageCache

    init(tasks: any TaskRepository) {
        cache = RemoteImageCache { path async throws(FamiliarError) in try await tasks.imageURL(path: path) }
    }

    func image(path: String) -> Image? {
        cache.image(forKey: path)
    }

    func load(path: String) async {
        await cache.load(key: path, path: path)
    }

    func insert(_ image: PreparedImage, familyID: UUID) {
        let base = "\(familyID.uuidString.lowercased())/\(image.id.uuidString.lowercased())"
        cache.insert(image.jpegData, forKey: "\(base).jpg")
        cache.insert(image.thumbnailData, forKey: "\(base)_thumb.jpg")
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

/// Bild aus dem Bucket `task-images` mit ruhigem Platzhalter.
struct TaskImageView: View {
    @Environment(TaskImageStore.self) private var images
    let path: String
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            if let image = images.image(path: path) {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(FamiliarColor.elevated)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(FamiliarColor.textTertiary)
                    }
            }
        }
        .task(id: path) { await images.load(path: path) }
        .familiarContentSwap(value: images.image(path: path) != nil)
    }
}
