import Foundation
import UIKit

/// 写真の実体を端末に保存する（10_アプリ設計.md AD-05）。
///
/// フェーズ1では端末ローカルのみ。フェーズ2で Blob Storage に上げ、
/// `Photo.blobUrl` を埋める。そのときに備えて、**保存時点で縮小・圧縮しておく**
/// （元のままだと1枚数MBになり、転送量とBlobの容量を無駄に食う）。
enum PhotoStore {

    /// 長辺の上限。ふりかえりで見るには十分で、通信量も抑えられる
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.8

    enum StoreError: Error, CustomStringConvertible {
        case encodingFailed
        var description: String {
            switch self {
            case .encodingFailed: "写真を保存できませんでした"
            }
        }
    }

    /// 保存先。ユーザーには見せないがバックアップ対象にしたいので Application Support
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path()) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// 縮小して保存し、ファイル名を返す
    @discardableResult
    static func save(_ image: UIImage) throws -> String {
        guard let data = resized(image).jpegData(compressionQuality: jpegQuality) else {
            throw StoreError.encodingFailed
        }
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: directory.appending(path: fileName), options: .atomic)
        return fileName
    }

    static func load(_ fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: fileName).path())
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }

    /// 長辺が `maxDimension` を超えていれば縮小する
    static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
