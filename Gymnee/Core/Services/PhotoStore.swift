import Foundation
import UIKit

/// ローカル写真ストレージ（オフラインファースト）。
/// Documents/photos 配下に JPEG 保存し、ファイル名を SwiftData に持たせる。
/// 同期時は localPhotoFilename を Supabase Storage / R2 へアップして photoURL を確定する想定（§9-2）。
enum PhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 画像を保存し、ファイル名を返す。失敗時 nil。
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.8) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    /// ファイル名から画像を読み込む。
    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
