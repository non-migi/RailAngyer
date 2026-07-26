import Foundation

/// APIの接続先。
///
/// 身内用の1環境しかないので設定画面には出さない。
/// ローカルのAPIに向けたいときだけ `RAILANGYER_API_BASE_URL` を渡す
/// （例: `http://localhost:5199`。UIテストやシミュレータでの動作確認用）。
enum ApiConfiguration {

    static let productionBaseURL = URL(string: "https://railangyer.azurewebsites.net")!

    static var baseURL: URL {
        guard let raw = ProcessInfo.processInfo.environment["RAILANGYER_API_BASE_URL"],
              let url = URL(string: raw) else { return productionBaseURL }
        return url
    }
}
