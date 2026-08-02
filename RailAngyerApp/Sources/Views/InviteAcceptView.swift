import SwiftUI

/// 共有されたリンクからアプリを開いたときに出す、参加の確認（SC-22）。
///
/// **リンクを踏んだだけで勝手に参加させない。** 表示名を決めてもらう必要があるし、
/// いま遊んでいるルームから移ることになる人もいる。
/// ただし手順は「名前を入れて、押す」だけに留める。
struct InviteAcceptView: View {

    let invitation: InviteLink.Invitation
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canJoin: Bool {
        !isWorking && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// すでにこのルームにいるなら、入り直す必要はない
    private var isAlreadyHere: Bool {
        sync.isJoined && store.room?.inviteCode == invitation.inviteCode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(invitation.roomName ?? "レイルアンギャー")
                            .font(.headline)
                        Text("招待コード　\(invitation.inviteCode)")
                            .font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("誘われているルーム")
                }

                if isAlreadyHere {
                    Section {
                        Label("すでにこのルームにいます", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        TextField("表示名", text: $displayName)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("あなたの名前")
                    } footer: {
                        Text("ルームの中で表示されます。"
                             + (sync.isJoined
                                ? "\n**いま参加しているルームからは抜けます。**"
                                  + "この端末の記録は残ります。"
                                : ""))
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("ルームへの招待")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("あとで") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAlreadyHere {
                        Button("閉じる") { dismiss() }
                    } else if isWorking {
                        ProgressView()
                    } else {
                        Button("参加する") { Task { await join() } }
                            .disabled(!canJoin)
                    }
                }
            }
            .onAppear {
                if displayName.isEmpty {
                    displayName = store.room?.members.first { $0.isMe }?.displayName ?? ""
                }
            }
        }
    }

    private func join() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await sync.join(inviteCode: invitation.inviteCode,
                                displayName: displayName.trimmingCharacters(
                                    in: .whitespacesAndNewlines))
            Telemetry.roomJoined()
            store.reloadSchedules()
            dismiss()
        } catch let error as ApiError {
            errorMessage = message(for: error)
        } catch {
            errorMessage = "参加できませんでした。電波の届くところで試してください。"
        }
    }

    private func message(for error: ApiError) -> String {
        if case .server(_, let detail) = error {
            switch detail?.error {
            case "invalid_invite_code":
                return "招待コードが違います。リンクが古いかもしれません。"
            case "display_name_taken":
                return "その名前はすでに使われています。別の名前にしてください"
            default:
                return detail?.message ?? error.message
            }
        }
        return error.message
    }
}
