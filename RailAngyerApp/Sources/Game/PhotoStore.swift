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
    ///
    /// > ⚠️ **パスを文字列にするときは `path(percentEncoded: false)` を使う。**
    /// > `path()` の既定はパーセントエンコードで、保存先は
    /// > 「Application Support」＝**空白を含む**ため `Application%20Support` になる。
    /// > `FileManager` も `UIImage(contentsOfFile:)` もその名前のファイルを見つけられない。
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path(percentEncoded: false)) {
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

    /// すでにJPEGになっているデータを、そのまま保存する。
    /// **仲間から取り込んだ写真用。** 上げる側で縮小済みなので、ここでは触らない
    @discardableResult
    static func save(data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: directory.appending(path: fileName), options: .atomic)
        return fileName
    }

    /// 保存してある実体。上げるときに読む
    static func data(of fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: url(of: fileName))
    }

    static func load(_ fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        // **URLから直接読む。** パスを文字列に落とすとエンコードの扱いで取りこぼす
        // （保存先に空白が入っており、実際に読めなくなっていた）
        guard let data = try? Data(contentsOf: url(of: fileName)) else { return nil }
        return UIImage(data: data)
    }

    /// 保存したファイルの場所
    static func url(of fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    /// 実体があるか。記録の掃除や検証に使う
    static func exists(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && FileManager.default.fileExists(atPath: url(of: fileName).path(percentEncoded: false))
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }

    /// 長辺が `maxDimension` を超えていれば縮小する。
    ///
    /// > ⚠️ **倍率を1に固定する。** 既定では端末の倍率（3倍など）で描かれるため、
    /// > 1600ptのつもりが4800ピクセルで保存される。容量が9倍になる
    static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
