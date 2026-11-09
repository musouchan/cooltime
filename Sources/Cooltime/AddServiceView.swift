import SwiftUI
import CooltimeCore

/// 使っているものだけを自分で選ぶ。選ぶまで何も取得しない。
struct AddServiceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var search = ""
    @State private var selectedCategory: ServiceCategory?
    let onAdded: (UUID) -> Void

    private var sections: [ServiceSection] {
        ServiceCategory.sections(from: Catalog.all, search: search, selected: selectedCategory)
    }

    private func categoryButton(_ category: ServiceCategory?, count: Int) -> some View {
        let selected = selectedCategory == category
        return Button {
            search = ""
            selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category?.symbol ?? "square.grid.2x2")
                    .frame(width: 18)
                Text(category?.rawValue ?? "すべて")
                Spacer(minLength: 0)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("サービスの追加").font(.title3).fontWeight(.semibold)
            Text("使っているものだけ選んでください。追加するまで、通信はしません。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("サービス名を検索（\(Catalog.all.count)件）", text: $search)
                .textFieldStyle(.roundedBorder)
                .onChange(of: search) { value in
                    if !value.isEmpty { selectedCategory = nil }
                }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("目次").font(.headline).padding(.horizontal, 10)
                    ScrollView {
                        VStack(spacing: 2) {
                            categoryButton(nil, count: Catalog.all.count)
                            ForEach(ServiceCategory.allCases) { category in
                                let count = Catalog.all.filter { ServiceCategory.category(for: $0) == category }.count
                                if count > 0 { categoryButton(category, count: count) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 176)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(selectedCategory?.rawValue ?? "すべてのサービス").font(.headline)
                        Spacer()
                        Text("\(sections.reduce(0) { $0 + $1.services.count })件")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if sections.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(sections) { section in
                                Section(section.category.rawValue) {
                                    ForEach(section.services) { s in
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
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 420)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加（\(picked.count)件）") {
                    var last: UUID?
                    for s in Catalog.all where picked.contains(s.id) { last = model.add(serviceID: s.id).id }
                    if let last { onAdded(last) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(picked.isEmpty)
            }
        }
        .padding(20).frame(width: 780)
    }
}
