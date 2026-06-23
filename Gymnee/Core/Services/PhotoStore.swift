import Foundation
import UIKit
import ImageIO

/// ローカル写真ストレージ（オフラインファースト）。
/// Documents/photos 配下に JPEG 保存し、ファイル名を SwiftData に持たせる。
/// 同期時は localPhotoFilename を Supabase Storage / R2 へアップして photoURL を確定する想定（§9-2）。
enum PhotoStore {
    /// load() のデコード結果キャッシュ（body から毎フレーム呼ばれてもディスクI/O＋デコードを繰り返さない）。
    private static let cache = NSCache<NSString, UIImage>()

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
            cache.setObject(image, forKey: filename as NSString)
            return filename
        } catch {
            return nil
        }
    }

    /// 画像 Data を最大辺 maxPixel へ効率的にダウンサンプル（フルデコードせずメモリ節約）。
    /// 高解像度 HEIC 等を UIImage(data:) でそのままデコードすると数百MBになり OOM 強制終了するため、
    /// 取り込み時は必ずこれを通す。背景スレッドから呼ぶこと。
    static func downsample(data: Data, maxPixel: CGFloat = 1280) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Data をダウンサンプルして保存（取り込みフロー用）。失敗時 nil。
    @discardableResult
    static func saveDownsampled(data: Data, maxPixel: CGFloat = 1280, quality: CGFloat = 0.8) -> String? {
        guard let image = downsample(data: data, maxPixel: maxPixel) else { return nil }
        return save(image, quality: quality)
    }

    /// リモートから取得したバイト列を、指定ファイル名でローカルに書き戻す（再インストール後の復元用）。
    @discardableResult
    static func writeData(_ data: Data, as filename: String) -> UIImage? {
        let url = directory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        let image = UIImage(data: data)
        if let image { cache.setObject(image, forKey: filename as NSString) }
        return image
    }

    /// ローカルにファイルが存在するか（キャッシュ含む）。
    static func exists(_ filename: String?) -> Bool {
        guard let filename else { return false }
        if cache.object(forKey: filename as NSString) != nil { return true }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path)
    }

    /// ファイル名から画像を読み込む（キャッシュ優先）。
    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        cache.removeObject(forKey: filename as NSString)
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
