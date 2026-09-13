import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.fill") }
            CadenceView()
                .tabItem { Label("步频器", systemImage: "metronome.fill") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.fill") }
        }
    }
}
