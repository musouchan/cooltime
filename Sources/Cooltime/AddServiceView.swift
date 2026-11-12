import SwiftUI
import CooltimeCore

/// 使っているものだけを自分で選ぶ。選ぶまで何も取得しない。
struct AddServiceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var search = ""
    let onAdded: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("サービスの追加").font(.title3).fontWeight(.semibold)
            Text("使っているものだけ選んでください。追加するまで、サービスの情報の取得はしません（ロゴだけ、各サービスの公式サイトから取得して、この Mac に保存します）。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("サービス名を検索（\(Catalog.available.count)件）", text: $search)
                .textFieldStyle(.roundedBorder)
            List(Catalog.available.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { s in
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
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加") {
                    var last: UUID?
                    for s in Catalog.available where picked.contains(s.id) { last = model.add(serviceID: s.id).id }
                    if let last { onAdded(last) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(picked.isEmpty)
            }
        }
        .padding(20).frame(width: 460)
        // ロゴが無いものは、開いたときに取り始める（取れたものから、順に、頭文字がロゴに変わる）
        .task { await ServiceIconStore.prefetch(Catalog.available) }
    }
}
