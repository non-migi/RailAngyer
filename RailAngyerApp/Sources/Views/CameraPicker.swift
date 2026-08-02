import SwiftUI
import UIKit

/// 駅での撮影（SC-08 / SC-09）。
///
/// SwiftUI にカメラの標準部品が無いため `UIImagePickerController` を包む。
/// **シミュレータにはカメラが無いので、その場合は写真ライブラリに切り替える**
/// （動作確認を止めないため）。
struct CameraPicker: UIViewControllerRepresentable {

    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isCameraAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// 撮った写真を並べる小さな一覧
/// 撮った写真の帯。**押すと大きく見られる。**
/// 小さいまま並べるだけでは、何が写っているのか確かめられない
struct PhotoStrip: View {
    let fileNames: [String]
    /// 大きく見るときに添える駅名
    var stationName: String = ""

    @State private var opened: PhotoGalleryView.Item?

    private var items: [PhotoGalleryView.Item] {
        fileNames.map { PhotoGalleryView.Item(fileName: $0, stationName: stationName,
                                              takenAt: Date()) }
    }

    var body: some View {
        if !fileNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            opened = item
                        } label: {
                            if let image = PhotoStore.load(item.fileName) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 64)
            .fullScreenCover(item: $opened) { item in
                PhotoViewerView(items: items, current: item)
            }
        }
    }
}
