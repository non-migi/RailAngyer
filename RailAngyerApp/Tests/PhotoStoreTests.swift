import Testing
import UIKit
import Foundation
@testable import RailAngyerApp

/// 写真の保存と読み出し（`PhotoStore`）。
///
/// **保存できても読めなければ、写真はどこにも出ない。**
/// 保存先は「Application Support」＝空白を含むため、
/// パスをパーセントエンコードしたまま渡すとファイルが見つからない。
/// 実際にそれで「撮ったのに1枚も表示されない」状態になっていた。
struct PhotoStoreTests {

    private func image(_ size: CGSize = CGSize(width: 40, height: 30)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test("保存した写真を読み出せる")
    func savesAndLoads() throws {
        let fileName = try PhotoStore.save(image())
        defer { PhotoStore.delete(fileName) }

        // ここが通らないと、地図のピンも一覧も帯もすべて空になる
        let loaded = PhotoStore.load(fileName)

        #expect(loaded != nil, "保存した写真を読み出せない")
    }

    @Test("保存先に空白が入っていても読める")
    func handlesPathWithSpaces() throws {
        // 「Application Support」に空白がある。パスをエンコードしたまま渡すと見つからない
        #expect(PhotoStore.directory.path(percentEncoded: false).contains(" "))

        let fileName = try PhotoStore.save(image())
        defer { PhotoStore.delete(fileName) }

        #expect(PhotoStore.exists(fileName), "保存した実体が見つからない")
        #expect(PhotoStore.load(fileName) != nil)
    }

    @Test("消したら読めなくなる")
    func deletes() throws {
        let fileName = try PhotoStore.save(image())

        PhotoStore.delete(fileName)

        #expect(PhotoStore.load(fileName) == nil)
        #expect(!PhotoStore.exists(fileName))
    }

    @Test("無いファイル名を渡しても落ちない")
    func toleratesMissingFile() {
        #expect(PhotoStore.load("") == nil)
        #expect(PhotoStore.load("\(UUID().uuidString).jpg") == nil)
        #expect(!PhotoStore.exists(""))
    }

    @Test("長い辺は縮めて保存する")
    func resizesLargeImages() throws {
        let big = image(CGSize(width: 4000, height: 3000))

        let fileName = try PhotoStore.save(big)
        defer { PhotoStore.delete(fileName) }
        let loaded = try #require(PhotoStore.load(fileName))

        #expect(max(loaded.size.width, loaded.size.height) <= PhotoStore.maxDimension + 1)
    }
}
