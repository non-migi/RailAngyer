import Foundation

/// コースを「国 → 都道府県 → 路線」の順にたどれる形へ並べ替える。
///
/// **路線名を平らに並べたままでは選べなくなる**ため、住んでいる場所から絞り込めるようにする。
/// いまは日本の6路線だけだが、国を最上位に置いてあるので、
/// 日本の外の路線が増えても同じ画面で扱える（都道府県にあたる段は `region`）。
///
/// 都道府県をまたぐ路線（阪急京都本線＝大阪府・京都府）は、
/// **通るすべての県の下に出す**。「大阪から歩く」人も「京都から歩く」人も見つけられる。
struct CourseDirectory {

    struct Region: Identifiable {
        let id: String
        let name: String
        let courses: [Course]
    }

    struct Country: Identifiable {
        let id: String
        let name: String
        let regions: [Region]

        /// この国にあるコースの数（県をまたぐ路線も1本として数える）
        var courseCount: Int { Set(regions.flatMap { $0.courses.map(\.name) }).count }
    }

    let countries: [Country]

    init(courses: [Course]) {
        let byCountry = Dictionary(grouping: courses) { $0.countryCode }

        countries = byCountry
            .map { code, list -> Country in
                var byRegion: [String: [Course]] = [:]
                for course in list {
                    for region in course.regionNamesForDisplay {
                        byRegion[region, default: []].append(course)
                    }
                }
                let regions = byRegion
                    .map { name, list in
                        Region(id: "\(code)/\(name)", name: name,
                               courses: list.sorted { $0.stations.count > $1.stations.count })
                    }
                    .sorted { Self.regionOrder($0.name) < Self.regionOrder($1.name) }

                return Country(id: code,
                               name: list.first?.countryName ?? code,
                               regions: regions)
            }
            // 日本を先頭に。以降は国名の順
            .sorted {
                if ($0.id == "JP") != ($1.id == "JP") { return $0.id == "JP" }
                return $0.name < $1.name
            }
    }

    /// このコースを含む国
    func country(of course: Course) -> Country? {
        countries.first { $0.id == course.countryCode }
    }

    /// 「大阪府・京都府」のような表示
    static func regionText(_ course: Course) -> String {
        course.regionNamesForDisplay.joined(separator: "・")
    }

    /// 都道府県の並び順（北から南へ。全国地方公共団体コードと同じ順）。
    /// 一覧に無い名前（日本の外）は名前順で後ろに回す
    private static func regionOrder(_ name: String) -> String {
        guard let index = prefectures.firstIndex(of: name) else { return "z\(name)" }
        return String(format: "a%02d", index)
    }

    private static let prefectures = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
        "岐阜県", "静岡県", "愛知県", "三重県",
        "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
        "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県",
        "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
    ]
}
