import SwiftUI

@main
struct TempoRunApp: App {
    @StateObject private var coordinator = RunCoordinator.shared
    @StateObject private var store = PersistenceStore.shared
    @StateObject private var subscriptions = SubscriptionManager.shared
    @State private var showSummary = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(coordinator)
                .environmentObject(store)
                .environmentObject(subscriptions)
                .preferredColorScheme(colorScheme)
                .tint(.accentColor)
                .onOpenURL { url in
                    if url.scheme == "temporun", url.host == "strava" {
                        Task { _ = await StravaService.shared.handleCallback(url) }
                    } else if url.scheme == "temporun", url.host == "cmd" {
                        switch url.path {
                        case "/pause": coordinator.session?.pause()
                        case "/resume": coordinator.session?.resume()
                        case "/stop": coordinator.session?.stopAndSave()
                        case "/up": coordinator.session?.adjustCurrentStageCadence(by: 5)
                        case "/down": coordinator.session?.adjustCurrentStageCadence(by: -5)
                        default: break
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .runDidFinish)) { _ in
                    showSummary = true
                }
                .sheet(isPresented: $showSummary) {
                    if let run = coordinator.lastFinishedRun {
                        RunSummaryView(run: run)
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            // 前台恢复时与 App Store / 本地 StoreKit Testing 对账
            if phase == .active {
                Task { await subscriptions.refresh() }
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.colorSchemeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
