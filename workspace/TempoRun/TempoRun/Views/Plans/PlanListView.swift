import SwiftUI

/// 训练计划库。
/// 免费版：自由跑、定频跑、1 个间歇模板；
/// Pro：进阶/更多间歇模板 + 无限自定义计划
struct PlanListView: View {
    let onStart: (TrainingPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customPlans: [TrainingPlan] = PersistenceStore.shared.plans()
    @State private var editing: TrainingPlan?
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false

    /// 进阶模板（Pro）
    private let advancedPlan = TrainingPlan(name: "步频进阶 · 节奏跑", type: .interval, stages: [
        Stage(type: .warmup, targetCadence: 150, duration: 480),
        Stage(type: .fast, targetCadence: 182, duration: 600),
        Stage(type: .cooldown, targetCadence: 140, duration: 300)
    ])

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 基础（免费）：自由跑 / 定频跑
                    Button { onStart(.freePlan); dismiss() } label: { PlanRow(plan: .freePlan) }
                    Button { onStart(.fixedPlan); dismiss() } label: { PlanRow(plan: .fixedPlan) }

                    // 免费版唯一的间歇模板
                    Button { onStart(.intervalTemplate); dismiss() } label: {
                        PlanRow(plan: .intervalTemplate)
                    }

                    // Pro：进阶间歇
                    Button {
                        if subs.isPro { onStart(advancedPlan); dismiss() } else { showPaywall = true }
                    } label: {
                        HStack {
                            PlanRow(plan: advancedPlan)
                            Spacer()
                            Image(systemName: "lock.fill").foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("内置训练")
                } footer: {
                    if !subs.isPro {
                        Text("免费版包含 1 个间歇模板，升级 Pro 解锁进阶课程与无限自定义计划。")
                    }
                }

                Section("我的计划") {
                    if subs.isPro {
                        ForEach(customPlans) { plan in
                            Button {
                                onStart(plan); dismiss()
                            } label: { PlanRow(plan: plan) }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    PersistenceStore.shared.deletePlan(id: plan.id)
                                    customPlans = PersistenceStore.shared.plans()
                                }
                            }
                        }
                        Button {
                            editing = TrainingPlan(name: "新间歇计划", type: .custom,
                                                   stages: [Stage(type: .warmup, targetCadence: 150, duration: 180),
                                                            Stage(type: .fast, targetCadence: 180, duration: 120),
                                                            Stage(type: .cooldown, targetCadence: 140, duration: 180)])
                        } label: {
                            Label("新建自定义计划", systemImage: "plus.circle.fill")
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill").foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("自定义训练计划").font(.subheadline.weight(.semibold))
                                    Text("Pro 可创建并保存无限个多阶段间歇计划")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Pro").font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.orange, in: Capsule()).foregroundColor(.white)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("训练模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(item: $editing) { plan in
                PlanEditorView(plan: plan) { saved in
                    PersistenceStore.shared.savePlan(saved)
                    customPlans = PersistenceStore.shared.plans()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(subscriptions: subs, feature: .unlimitedPlans)
            }
        }
    }
}

private struct PlanRow: View {
    let plan: TrainingPlan
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.subheadline.weight(.semibold))
                Text(stageSummary)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    private var stageSummary: String {
        let total = plan.stages.reduce(0) { $0 + $1.duration }
        return "\(plan.stages.count) 阶段 · \(Formatters.duration(total))"
    }
}

// MARK: - 计划编辑器（每阶段独立设置步频/时长）

struct PlanEditorView: View {
    @State var plan: TrainingPlan
    let onSave: (TrainingPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("计划名称") {
                    TextField("名称", text: $plan.name)
                }
                Section("阶段（热身/快跑/慢跑/冷身）") {
                    ForEach($plan.stages) { $stage in
                        StageEditorRow(stage: $stage)
                    }
                    .onDelete { plan.stages.remove(atOffsets: $0) }
                    .onMove { plan.stages.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        ForEach(StageType.allCases) { type in
                            Button(type.rawValue) {
                                plan.stages.append(Stage(type: type, targetCadence: 170, duration: 120))
                            }
                        }
                    } label: {
                        Label("添加阶段", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("编辑计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(plan); dismiss()
                    }
                }
            }
        }
    }
}

private struct StageEditorRow: View {
    @Binding var stage: Stage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("类型", selection: $stage.type) {
                ForEach(StageType.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Stepper(value: $stage.targetCadence, in: AppConstants.cadenceRange) {
                HStack {
                    Text("目标步频")
                    Spacer()
                    Text("\(stage.targetCadence) SPM").monospacedDigit().foregroundColor(.secondary)
                }
            }
            Stepper(value: Binding(get: { Int(stage.duration) },
                                   set: { stage.duration = TimeInterval($0) }),
                    in: 0...7200, step: 15) {
                HStack {
                    Text("时长")
                    Spacer()
                    Text(stage.duration == 0 ? "手动结束" : Formatters.duration(stage.duration))
                        .monospacedDigit().foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
