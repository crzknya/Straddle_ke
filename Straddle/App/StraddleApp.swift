import SwiftUI

@main
struct StraddleApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(StraddleTheme.purple)
        }
    }
}

enum RootSheet: String, Identifiable {
    case newSession, startLive, live
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var sheet: RootSheet?

    var body: some View {
        TabView {
            NavigationStack { DashboardView(sheet: $sheet) }
                .modifier(LiveBannerInset(open: { sheet = .live }))
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
            NavigationStack { HistoryView(sheet: $sheet) }
                .modifier(LiveBannerInset(open: { sheet = .live }))
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { AnalyticsView() }
                .modifier(LiveBannerInset(open: { sheet = .live }))
                .tabItem { Label("Analytics", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .toolbarBackground(StraddleTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $sheet) { item in
            NavigationStack {
                switch item {
                case .newSession:
                    SessionFormView(template: store.newSessionTemplate())
                case .startLive:
                    StartLiveSessionView(template: store.newSessionTemplate()) { sheet = .live }
                case .live:
                    LiveSessionView()
                }
            }
            .interactiveDismissDisabled(item != .live)
        }
        .onChange(of: store.liveSession == nil) { _, ended in
            // Сессия завершена или удалена — закрываем окно живой сессии.
            if ended, sheet == .live { sheet = nil }
        }
        .alert("Storage Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError?.localizedDescription ?? "Unknown error")
        }
    }
}

/// Плашка текущей живой сессии внизу каждой вкладки.
struct LiveBannerInset: ViewModifier {
    @EnvironmentObject private var store: SessionStore
    let open: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let live = store.liveSession {
                Button(action: open) { LiveSessionBanner(live: live) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Кнопка «+» в навбаре: живая сессия или запись прошедшей.
struct AddSessionMenu: View {
    @EnvironmentObject private var store: SessionStore
    @Binding var sheet: RootSheet?

    var body: some View {
        Menu {
            if store.liveSession == nil {
                Button { sheet = .startLive } label: { Label("Start live session", systemImage: "play.circle") }
            } else {
                Button { sheet = .live } label: { Label("Open live session", systemImage: "stopwatch") }
            }
            Button { sheet = .newSession } label: { Label("Add completed session", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus").fontWeight(.bold)
        }
        .accessibilityLabel("Add session")
    }
}
