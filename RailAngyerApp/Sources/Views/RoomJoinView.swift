import SwiftUI
import RailAngyerCore

/// ルームへの参加とルーム作成（SC-19）。
///
/// 招待コードだけで入れる軽さを保つ（`03_Azure構成と料金.md` §5）。
/// 参加すると**区間と最大出目はサーバーのものに合わせる**（T-06）ため、
/// 端末ごとに違う盤面で遊んでしまうことがない。
///
/// **参加したら、遊ぶ旅もそのルームの旅に切り替わる。**
/// 端末で進めていた旅を残したまま取り込むと、自分の記録とルームの記録が
/// ひとつの盤面に混ざる（訪問済みの駅もターン数も合わなくなる）。
/// 参加の前に、いまの旅を「過去の旅」へ畳んでから切り替える。
struct RoomJoinView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case join = "招待コードで参加"
        case create = "新しく作る"
    }

    @State private var mode: Mode = .join
    @State private var inviteCode = ""
    @State private var displayName = ""
    @State private var roomName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingLeaveConfirm = false
    @State private var showingSwitchConfirm = false

    /// 端末で進めている旅があるか。参加すると盤面はルームのものに入れ替わる
    private var hasLocalProgress: Bool { !(store.room?.turns.isEmpty ?? true) }

    private var canSubmit: Bool {
        guard !isWorking, !displayName.trimmed.isEmpty else { return false }
        switch mode {
        case .join:   return inviteCode.trimmed.count >= 4
        case .create: return !roomName.trimmed.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if sync.isJoined {
                    joinedSection
                } else {
                    modeSection
                    inputSection
                    switchNoticeSection
                    submitSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("みんなで遊ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                if displayName.isEmpty {
                    displayName = store.room?.members.first { $0.isMe }?.displayName ?? ""
                }
                if roomName.isEmpty, let course = store.room?.course?.name {
                    roomName = "\(course)ツアー"
                }
            }
            .confirmationDialog("このルームから抜けますか",
                                isPresented: $showingLeaveConfirm, titleVisibility: .visible) {
                Button("抜ける", role: .destructive) { leave() }
            } message: {
                Text("未送信の記録は送られないまま消えます。端末の記録は残ります。")
            }
            .confirmationDialog("いまの旅を保存して参加しますか",
                                isPresented: $showingSwitchConfirm, titleVisibility: .visible) {
                Button("保存して参加する") { Task { await submit() } }
            } message: {
                Text("盤面はルームの旅に切り替わります。いま進めている旅は「過去の旅」に保存され、写真も残ります。")
            }
        }
    }

    // MARK: - 参加済み

    @ViewBuilder
    private var joinedSection: some View {
        Section {
            LabeledContent("ルーム", value: store.room?.name ?? "-")
            // どの旅をみんなで歩いているのかは、ルーム名だけでは分からない
            LabeledContent("コース", value: store.room?.course?.name ?? "-")
            LabeledContent("区間", value: rangeText)
            if let code = store.room?.inviteCode {
                LabeledContent("招待コード", value: code)
                    .textSelection(.enabled)
            }
            // **数字だけでは、放っておいていいのか分からない。**
            // 中身はサイコロ・到着・写真・お題・予定が混ざった送信キューの残り
            LabeledContent("送信待ちの記録",
                           value: sync.pendingCount == 0 ? "なし" : "\(sync.pendingCount) 件")
        } header: {
            Text("いま参加しているルーム")
        } footer: {
            if sync.pendingCount > 0 {
                Text("「送信待ちの記録」は、まだ仲間に届いていないサイコロ・到着・写真・お題・予定の数です。"
                     + "電波が戻ればまとめて送られるので、このままで大丈夫です。")
            }
        }

        Section("メンバー") {
            ForEach(members) { member in
                HStack {
                    Text(member.displayName)
                    if member.isMe {
                        Text("あなた").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            Button("最新の状態にする") { Task { await refresh() } }
                .disabled(isWorking)
            Button("このルームから抜ける", role: .destructive) { showingLeaveConfirm = true }
        } footer: {
            Text("招待コードは仲間にだけ伝えてください。コードを知っている人は誰でも参加できます。")
        }
    }

    private var members: [Member] {
        (store.room?.members ?? []).sorted { $0.joinedAt < $1.joinedAt }
    }

    // MARK: - 未参加

    private var modeSection: some View {
        Section {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        Section("あなたの名前") {
            TextField("表示名", text: $displayName)
                .textInputAutocapitalization(.never)
        }

        switch mode {
        case .join:
            Section("招待コード") {
                TextField("ABC123", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }
        case .create:
            Section {
                TextField("夏の南北線ツアー", text: $roomName)
            } header: {
                Text("ルーム名")
            } footer: {
                Text("いまの区間（\(rangeText)）と最大出目 \(store.room?.diceMax ?? 6) で作ります。プレイを始めると変更できません。")
            }
        }
    }

    private var rangeText: String {
        let start = store.room?.startStation?.name ?? "-"
        let goal = store.room?.goalStation?.name ?? "-"
        return "\(start) → \(goal)"
    }

    /// 参加すると盤面が入れ替わることを、押す前に伝える。
    /// 押したあとで「進めていた旅が消えた」と見えるのがいちばん困る
    @ViewBuilder
    private var switchNoticeSection: some View {
        if mode == .join, hasLocalProgress {
            Section {
                Label("参加すると、ルームの旅に切り替わります", systemImage: "arrow.triangle.swap")
                    .font(.subheadline.weight(.semibold))
                Text(switchNoticeText)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var switchNoticeText: String {
        let progress = "\(store.visitedCount)駅・\(DurationText.text(store.timing.elapsedSeconds))"
        return "いま進めている旅（\(progress)）は「過去の旅」に保存されます。写真もそのまま残ります。"
    }

    private var submitSection: some View {
        Section {
            Button {
                // 進めている旅があるときだけ、切り替わることを確かめてから進む
                if mode == .join, hasLocalProgress {
                    showingSwitchConfirm = true
                } else {
                    Task { await submit() }
                }
            } label: {
                HStack {
                    Text(mode == .join ? "参加する" : "作る")
                    if isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canSubmit)
        } footer: {
            // F1 とサーバーレスDBは寝ている。初回だけ待たされることを先に伝えておく
            Text("最初の通信はサーバーの起動待ちで1分ほどかかることがあります。")
        }
    }

    // MARK: - 操作

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            switch mode {
            case .join:
                // **畳むのは参加より先。** 参加したあとに畳むと、リセットが
                // 参加先のルーム宛てに積まれ、みんなの記録をサーバーから消してしまう
                // （`resetProgress` は `enqueueReset` を通す。未参加のときは何も積まれない）
                if hasLocalProgress { store.resetProgress(archive: true) }

                try await sync.join(inviteCode: inviteCode.trimmed.uppercased(),
                                    displayName: displayName.trimmed)
                Telemetry.roomJoined()
                // 予定はルームで共有される。参加したその場で一覧に出す
                store.reloadSchedules()
            case .create:
                // 作成には駅のサーバーIDが要る。まだ無ければ先にマスタを取りに行く
                if store.room?.course?.serverId == nil { await sync.pullMaster() }

                guard let room = store.room,
                      let courseId = room.course?.serverId,
                      let start = room.startStation?.serverId,
                      let goal = room.goalStation?.serverId else {
                    errorMessage = "駅マスタを取得できませんでした。通信を確かめてください。"
                    return
                }
                _ = try await sync.createRoom(CreateRoomRequest(
                    courseId: courseId,
                    name: roomName.trimmed,
                    startStationId: start,
                    goalStationId: goal,
                    diceMax: room.diceMax,
                    displayName: displayName.trimmed))
                // 作る側は、いまの旅をそのままみんなの旅にする（切り替えは起きない）
                store.reloadSchedules()
            }
            dismiss()
        } catch let error as ApiError {
            errorMessage = message(for: error)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func message(for error: ApiError) -> String {
        if case .server(let status, let detail) = error {
            switch detail?.error {
            case "invalid_invite_code": return "招待コードが違います"
            case "display_name_taken":  return "その名前はすでに使われています。別の名前にしてください"
            default: return detail?.message ?? "サーバーエラー（\(status)）"
            }
        }
        return error.message
    }

    private func refresh() async {
        isWorking = true
        defer { isWorking = false }
        await sync.push()
        await sync.pullRoom()
        await sync.pull()
    }

    private func leave() {
        do {
            try sync.leave()
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
