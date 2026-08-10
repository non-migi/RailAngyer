import SwiftUI
import SceneKit
import UIKit

/// 転がるサイコロ（SC-05）。
///
/// 立方体を実際に回転させ、出た目の面を手前に向けて止める。
/// **出目は先に決まっている**（`GameEngine.roll()` の結果）ので、
/// 演出は「決まった目に着地させる」だけ。乱数を演出側で引き直さない。
///
/// 最大出目が7〜9のときは立方体で表せないため、数字が回る演出に切り替える。
struct DiceRollView: View {
    let value: Int
    /// 転がり終わったときに呼ばれる
    var onSettled: () -> Void = {}

    var body: some View {
        Group {
            if (1...6).contains(value) {
                DiceSceneView(value: value, onSettled: onSettled)
            } else {
                NumericDiceView(value: value, onSettled: onSettled)
            }
        }
        .frame(width: 140, height: 140)
    }
}

// MARK: - 立方体（1〜6）

private struct DiceSceneView: UIViewRepresentable {
    let value: Int
    let onSettled: () -> Void

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.makeScene()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        context.coordinator.roll(to: value)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSettled: onSettled) }

    final class Coordinator {
        private let onSettled: () -> Void
        private let dice = SCNNode()

        init(onSettled: @escaping () -> Void) { self.onSettled = onSettled }

        func makeScene() -> SCNScene {
            let scene = SCNScene()

            let box = SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0.28)
            // SCNBox のマテリアル順: 前(+Z) 右(+X) 後(-Z) 左(-X) 上(+Y) 下(-Y)
            // 向かい合う面の和が7になるように割り当てる（1-6 / 2-5 / 3-4）
            box.materials = [1, 2, 6, 5, 3, 4].map { face in
                let material = SCNMaterial()
                material.diffuse.contents = DiePipTexture.image(for: face)
                material.locksAmbientWithDiffuse = true
                return material
            }
            dice.geometry = box
            // 転がり始める前の姿勢を少し傾けておく
            dice.eulerAngles = SCNVector3(-0.5, 0.6, 0.2)
            scene.rootNode.addChildNode(dice)

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 38
            camera.position = SCNVector3(0, 0, 6.4)
            scene.rootNode.addChildNode(camera)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 700
            key.position = SCNVector3(4, 6, 6)
            key.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(key)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 620
            scene.rootNode.addChildNode(ambient)

            return scene
        }

        /// 静止時の傾き。真正面を向くと平面に見えてしまうため、わずかに傾けて立体に見せる。
        /// **z（横倒し）は 0 にする。** 入れるとサイコロが斜めのまま止まって見え、
        /// 「まだ転がり切っていない」ように読める
        private static let restTilt: (x: Float, y: Float, z: Float) = (0.10, -0.13, 0)

        /// 指定の目を手前に向けて止める
        func roll(to value: Int) {
            let target = Self.orientation(for: value)
            // 何回転か余分に回してから目的の姿勢へ収める
            let spins = SCNVector3(target.x + .pi * 4 + Self.restTilt.x,
                                   target.y + .pi * 6 + Self.restTilt.y,
                                   .pi * 2 + Self.restTilt.z)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.15
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            SCNTransaction.completionBlock = { [onSettled] in
                DispatchQueue.main.async {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSettled()
                }
            }
            dice.eulerAngles = spins
            SCNTransaction.commit()
        }

        /// その目の面を +Z（手前）に向けるための回転
        private static func orientation(for value: Int) -> (x: Float, y: Float) {
            switch value {
            case 1: (0, 0)                       // 前
            case 6: (0, .pi)                     // 後
            case 2: (0, -.pi / 2)                // 右
            case 5: (0, .pi / 2)                 // 左
            case 3: (.pi / 2, 0)                 // 上
            case 4: (-.pi / 2, 0)                // 下
            default: (0, 0)
            }
        }
    }
}

// MARK: - 数字（7〜9）

/// 立方体では表せない目のときの代替。数字が回って止まる
private struct NumericDiceView: View {
    let value: Int
    let onSettled: () -> Void

    @State private var angle: Double = 0
    @State private var shown = 1

    var body: some View {
        Text("\(shown)")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .frame(width: 120, height: 120)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.ink.opacity(0.35), lineWidth: 2))
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0.4, z: 0))
            .task {
                withAnimation(.easeOut(duration: 1.1)) { angle = 1080 }
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(90))
                    shown = Int.random(in: 1...9)
                }
                shown = value
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSettled()
            }
    }
}

// MARK: - 面のテクスチャ

/// サイコロの面（目のピップ）を描く
enum DiePipTexture {

    static func image(for value: Int, size: CGFloat = 256) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))

            let pipColor: UIColor = value == 1
                ? UIColor(red: 0.72, green: 0.16, blue: 0.16, alpha: 1)   // 1の目は赤
                : UIColor(red: 0.09, green: 0.15, blue: 0.25, alpha: 1)   // ロゴの濃紺
            pipColor.setFill()

            let radius = size * 0.075
            for (col, row) in positions(for: value) {
                let center = CGPoint(x: size * (0.25 + 0.25 * CGFloat(col)),
                                     y: size * (0.25 + 0.25 * CGFloat(row)))
                context.cgContext.fillEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
    }

    /// 3×3 のどこに点を打つか（列, 行）
    private static func positions(for value: Int) -> [(Int, Int)] {
        switch value {
        case 1: [(1, 1)]
        case 2: [(0, 0), (2, 2)]
        case 3: [(0, 0), (1, 1), (2, 2)]
        case 4: [(0, 0), (2, 0), (0, 2), (2, 2)]
        case 5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)]
        case 6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)]
        default: []
        }
    }
}
