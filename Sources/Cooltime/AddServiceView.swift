import SwiftUI
import CooltimeCore

/// 使っているものだけを自分で選ぶ。選ぶまで何も取得しない。
struct AddServiceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var search = ""
    @State private var logoStatus: String?
    @State private var fetching = false
    let onAdded: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("サービスの追加").font(.title3).fontWeight(.semibold)
            Text("使っているものだけ選んでください。追加するまで、通信はしません。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("サービス名を検索（\(Catalog.all.count)件）", text: $search)
                .textFieldStyle(.roundedBorder)
            List(Catalog.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { s in
                Toggle(isOn: Binding(get: { picked.contains(s.id) },
                                     set: { if $0 { picked.insert(s.id) } else { picked.remove(s.id) } })) {
                    HStack {
                        AppIconView(service: s, size: 24)
                        VStack(alignment: .leading) {
                            Text(s.name)
                            Text(s.hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 280)
            HStack(spacing: 8) {
                Button(fetching ? "取得中…" : "ロゴを取得") { fetchLogos() }
                    .disabled(fetching || ServiceIconStore.missing(Catalog.all).isEmpty)
                    .help("アプリが入っていないサービスのロゴを、各サービス自身の公式サイトから取得して、この Mac に保存します（押したときだけ接続します）")
                if let logoStatus { Text(logoStatus).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加") {
                    var last: UUID?
                    for s in Catalog.all where picked.contains(s.id) { last = model.add(serviceID: s.id).id }
                    if let last { onAdded(last) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(picked.isEmpty)
            }
        }
        .padding(20).frame(width: 460)
    }

    /// ロゴの無いサービスを、1つずつ取る。取れなかったものは、色つきの頭文字のまま。
    private func fetchLogos() {
        let targets = ServiceIconStore.missing(Catalog.all)
        fetching = true
        Task {
            var ok = 0
            for (i, s) in targets.enumerated() {
                logoStatus = "\(i + 1) / \(targets.count)"
                if await ServiceIconStore.fetch(s) { ok += 1 }
            }
            logoStatus = "\(ok) 件取得しました" + (ok < targets.count ? "（\(targets.count - ok) 件は、サイトに見つからなかったため、頭文字のままです）" : "")
            fetching = false
        }
    }
}
