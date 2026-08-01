import SwiftUI

/// コースを国 → 都道府県 → 路線の順にたどって選ぶ（予定を立てるとき）。
///
/// **どこを歩くかは場所から決まる。** 路線名を平らに並べても、
/// 増えるほど自分の街の路線を探しにくくなるため、地図と同じ順にたどらせる。
struct CoursePickerView: View {

    let courses: [Course]
    @Binding var selectedName: String
    @Environment(\.dismiss) private var dismiss

    private var directory: CourseDirectory { CourseDirectory(courses: courses) }

    var body: some View {
        List {
            Section {
                ForEach(directory.countries) { country in
                    NavigationLink {
                        regionList(country)
                    } label: {
                        LabeledContent {
                            Text("\(country.courseCount) 路線")
                        } label: {
                            Label(country.name, systemImage: "globe.asia.australia")
                        }
                    }
                }
            } footer: {
                Text("いまは日本だけです。国から選ぶ形にしてあるので、"
                     + "ほかの国の路線が増えても同じ手順で選べます。")
            }
        }
        .navigationTitle("コースを選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 都道府県の段
    private func regionList(_ country: CourseDirectory.Country) -> some View {
        List {
            Section {
                ForEach(country.regions) { region in
                    NavigationLink {
                        courseList(region)
                    } label: {
                        LabeledContent {
                            Text("\(region.courses.count) 路線")
                        } label: {
                            Label(region.name, systemImage: "map")
                        }
                    }
                }
            } footer: {
                Text("県をまたぐ路線は、通るどちらの県からも選べます。")
            }
        }
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 路線の段。選ぶとここで終わり
    private func courseList(_ region: CourseDirectory.Region) -> some View {
        List {
            ForEach(region.courses) { course in
                Button {
                    selectedName = course.name
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name).font(.body).foregroundStyle(.primary)
                            Text(courseDetail(course))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if course.name == selectedName {
                            Image(systemName: "checkmark").foregroundStyle(Theme.line)
                        }
                    }
                }
            }
        }
        .navigationTitle(region.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func courseDetail(_ course: Course) -> String {
        let stations = course.stationsInOrder
        var parts = ["\(stations.count)駅"]
        if let first = stations.first, let last = stations.last {
            parts.append(course.isLoop ? "\(first.name)から一周" : "\(first.name) 〜 \(last.name)")
        }
        if course.regionNamesForDisplay.count > 1 {
            parts.append(CourseDirectory.regionText(course))
        }
        return parts.joined(separator: "　")
    }
}
