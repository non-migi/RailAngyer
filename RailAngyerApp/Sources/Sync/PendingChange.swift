import Foundation
import SwiftData

/// 送信待ちの書き込み1件（11_API設計.md §4 送信キュー）。
///
/// <para>**プレイはキューの状態に依存しない。** ローカルへの保存が正で、
/// これは「あとでサーバーにも伝える」ための控えでしかない。</para>
///
/// 書き込みはすべて<b>クライアント生成のUUIDを主キーにした冪等なPUT</b>なので、
/// 素朴に再送してよい。同じ対象への更新が溜まったら古いものは捨てられる。
@Model
final class PendingChange {
    var id: UUID = UUID()
    var method: String = "PUT"
    /// `/rooms/{roomId}/turns/{turnId}` のような、ベースURLからの相対パス
    var path: String = ""
    var payload: Data?
    var createdAt: Date = Date()
    /// 同じ対象への更新をまとめるための鍵。ふつうはパスと同じ
    var targetKey: String = ""
    var attemptCount: Int = 0
    var lastError: String?

    init(method: String = "PUT", path: String, payload: Data?, createdAt: Date = Date()) {
        self.method = method
        self.path = path
        self.payload = payload
        self.createdAt = createdAt
        self.targetKey = "\(method) \(path)"
    }
}

/// キューの出し入れ。**保存はここでしかしない**（呼び出し側が保存忘れをしないように）
struct SyncQueue {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 積む。同じ対象への未送信があれば**置き換える**。
    /// 着地 → ミッション → 効果 と同じターンへ何度もPUTするため、
    /// 溜めたままだと圏外から戻ったときに古い内容まで送り直すことになる
    func enqueue(_ change: PendingChange) throws {
        let key = change.targetKey
        let existing = try context.fetch(
            FetchDescriptor<PendingChange>(predicate: #Predicate { $0.targetKey == key }))

        // 更新（PUT）は最初に積んだ時刻を引き継ぐ。順序は「操作した順」であってほしいため。
        // 削除は逆に「いま消した」ことが大事なので、古い時刻に戻さない
        //（戻すと、リセット後に積んだ記録より前に削除が飛んでしまう）
        if change.method == "PUT", let oldest = existing.min(by: { $0.createdAt < $1.createdAt }) {
            change.createdAt = oldest.createdAt
        }
        for old in existing { context.delete(old) }

        context.insert(change)
        try context.save()
    }

    /// 古い順。**送る順序は操作した順**でなければ、途中の状態が後から上書きしてしまう
    func pending() throws -> [PendingChange] {
        try context.fetch(FetchDescriptor<PendingChange>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
    }

    func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<PendingChange>())
    }

    func remove(_ change: PendingChange) throws {
        context.delete(change)
        try context.save()
    }

    func recordFailure(_ change: PendingChange, message: String) throws {
        change.attemptCount += 1
        change.lastError = message
        try context.save()
    }

    func removeAll() throws {
        for change in try pending() { context.delete(change) }
        try context.save()
    }
}
