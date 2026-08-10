import SwiftUI
import StoreKit

/// 開発者への応援（SC-28）。
///
/// **買っても何も起こらない。** それを隠さず先に書く。
/// 機能を解放すると期待させると、買ったあとに落胆させることになる。
struct SupportDeveloperView: View {

    @Bindable var tipJar: TipJar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("このアプリは1人で作っています。")
                            .font(.headline)
                        Text("駅の座標を調べ、コースを増やし、みんなで遊べるようにサーバーを動かしています。気に入っていただけたら、応援してもらえるとうれしいです。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    // **期待させない。** ここを曖昧にすると、買ったあとに落胆させる
                    Text("応援しても、機能が増えたり広告が消えたりはしません。気持ちだけを受け取る仕組みです。")
                }

                if tipJar.isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("読み込んでいます…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else if tipJar.isAvailable {
                    Section {
                        ForEach(tipJar.tiers) { tier in
                            Button {
                                Task { await tipJar.purchase(tier) }
                            } label: {
                                row(tier)
                            }
                            .buttonStyle(.plain)
                            .disabled(tipJar.isPurchasing)
                        }
                    } footer: {
                        Text("何度でも応援できます。")
                    }
                } else {
                    Section {
                        Text(tipJar.lastError
                             ?? "いまは応援を受け取れません。しばらくしてから開いてください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if tipJar.supportCount > 0 {
                    Section {
                        Label("これまで \(tipJar.supportCount) 回応援してもらいました",
                              systemImage: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mission)
                    } footer: {
                        Text("この記録はこの端末の中だけのものです。")
                    }
                }

                if let error = tipJar.lastError, tipJar.isAvailable {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("開発者を応援する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await tipJar.load() }
            .alert("ありがとうございます", isPresented: $tipJar.isThanking) {
                Button("どういたしまして") { }
            } message: {
                Text("いただいた気持ちは、コースを増やす手間とサーバーを動かす費用にあてます。")
            }
        }
    }

    private func row(_ tier: TipJar.Tier) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Theme.mission)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.caption).font(.body).foregroundStyle(.primary)
                Text(tier.product.displayPrice)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if tipJar.isPurchasing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
