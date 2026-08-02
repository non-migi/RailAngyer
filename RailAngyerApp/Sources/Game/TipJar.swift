import Foundation
import StoreKit
import SwiftUI

/// 開発者への応援（SC-28）。
///
/// **買っても何も起こらない。** 機能は1つも解放しない。
/// 気持ちを受け取るだけの仕組みで、遊びの中身には一切関わらせない。
///
/// > ⚠️ **Consumable（消耗型）にしてある。理由が2つある。**
/// > 1. 復元すべき「権利」が存在しないので、`Restore Purchases` の導線を作らずに済む
/// >    （Non-consumable にすると審査で必須になる）
/// > 2. **何度でも応援できる**。1回きりにする理由がない
/// >
/// > ここで機能を1つでも解放した瞬間、端末をまたぐ復元・検証・同期がついてくる。
/// > **何も起こらないままにしておくこと。**
@Observable
@MainActor
final class TipJar {

    /// 応援の段。金額は App Store Connect 側の設定が正で、ここでは並び順と言い回しだけ持つ
    struct Tier: Identifiable {
        let product: Product
        var id: String { product.id }

        /// 「コーヒー1杯ぶん」のような言い方。金額だけだと選びにくい
        var caption: String {
            switch product.id {
            case TipJar.productIDs[0]: "コーヒー1杯ぶん"
            case TipJar.productIDs[1]: "ランチ1回ぶん"
            case TipJar.productIDs[2]: "しっかり応援"
            default: "応援する"
            }
        }
    }

    static let productIDs = [
        "com.non-migi.RailAngyerApp.tip300",
        "com.non-migi.RailAngyerApp.tip600",
        "com.non-migi.RailAngyerApp.tip1000"
    ]

    private(set) var tiers: [Tier] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    /// 買えなかった理由。**遊びに関わらないので、出すだけで進行は止めない**
    private(set) var lastError: String?
    /// いま感謝を出しているか
    var isThanking = false

    /// これまで応援してくれた回数。**この端末の中だけの記録**。
    /// 権利ではないので、消えても誰も困らない（だから復元も要らない）
    private(set) var supportCount: Int

    private static let countKey = "supportCount"
    private var updates: Task<Void, Never>?

    init() {
        supportCount = UserDefaults.standard.integer(forKey: Self.countKey)

        // 購入の外から届く取引（承認待ちの承認など）も、受け取ったら必ず閉じる
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.countUp()
            }
        }
    }

    /// 応援できるかどうか。**まだ App Store に並んでいなければ何も出さない**
    var isAvailable: Bool { !tiers.isEmpty }

    func load() async {
        guard tiers.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: Self.productIDs)
            // 金額の安い順。並びが日によって変わると選びにくい
            tiers = products.sorted { $0.price < $1.price }.map(Tier.init)
            lastError = nil
        } catch {
            // 圏外でも設定画面は開ける。応援の欄が出ないだけ
            tiers = []
            lastError = "いまは応援を受け取れません。電波の届くところで開き直してください。"
        }
    }

    func purchase(_ tier: Tier) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await tier.product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "購入を確認できませんでした。"
                    return
                }
                // **何も解放しないので、確かめたらすぐ閉じる**
                await transaction.finish()
                countUp()
                lastError = nil
                isThanking = true

            case .userCancelled:
                lastError = nil
            case .pending:
                // 承認待ち（ファミリー共有など）。届いたら `Transaction.updates` が拾う
                lastError = "承認を待っています。"
            @unknown default:
                break
            }
        } catch {
            lastError = "購入を完了できませんでした。"
        }
    }

    private func countUp() {
        supportCount += 1
        UserDefaults.standard.set(supportCount, forKey: Self.countKey)
    }
}
