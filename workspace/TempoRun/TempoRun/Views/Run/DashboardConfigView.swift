import SwiftUI

/// 实时面板字段自定义（顺序 + 显隐）
struct DashboardConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fields = PersistenceStore.shared.settings.dashboardFields
    @State private var allFields = DashboardField.allCases

    var body: some View {
        NavigationStack {
            List {
                Section("已显示（拖动排序）") {
                    ForEach(fields) { field in
                        Label(field.rawValue, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .onMove { fields.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in
                        idx.map { fields[$0] }.forEach { f in fields.removeAll { $0 == f } }
                    }
                }
                Section("可添加") {
                    ForEach(allFields.filter { !fields.contains($0) }) { field in
                        Button {
                            fields.append(field)
                        } label: {
                            Label(field.rawValue, systemImage: "plus.circle")
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("自定义数据面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var s = PersistenceStore.shared.settings
                        s.dashboardFields = fields
                        PersistenceStore.shared.saveSettings(s)
                        dismiss()
                    }
                }
            }
        }
    }
}
