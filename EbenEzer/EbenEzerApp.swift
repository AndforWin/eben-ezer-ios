//
//  EbenEzerApp.swift
//  Eben-Ezer – Zeichen seiner Hilfe
//
//  „Bis hierher hat uns der HERR geholfen.“ (1. Samuel 7,12)
//

import SwiftUI

@main
struct EbenEzerApp: App {
    @StateObject private var store = Store()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(lock)
                .lockCover(lock)
                .preferredColorScheme(.light)
                .tint(Color.green800)
                .onChange(of: scenePhase) { phase in
                    lock.scenePhaseChanged(phase)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let id):
                        DetailView(id: id)
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .fullScreenCover(item: $store.editing) { target in
            EditView(original: target.testimonyID.flatMap { store.get($0) })
                .environmentObject(store)
                .environmentObject(lock)
                .lockCover(lock)
                .preferredColorScheme(.light)
                .tint(Color.green800)
        }
    }
}
