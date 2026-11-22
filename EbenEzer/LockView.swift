//
//  LockView.swift
//  Eben-Ezer
//
//  App-Sperre mit Face ID, Touch ID oder Gerätecode.
//

import SwiftUI
import LocalAuthentication

final class AppLock: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var locked: Bool
    @Published var message: String?

    private var backgroundedAt: Date?
    private var authRunning = false
    private var autoPrompt: Bool

    init() {
        let on = UserDefaults.standard.bool(forKey: "lock")
        enabled = on
        locked = on
        autoPrompt = on
    }

    var canAuthenticate: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func setEnabled(_ on: Bool) {
        if on && !canAuthenticate {
            message = "Bitte richte zuerst einen Gerätecode (und ggf. Face ID) in den iPhone-Einstellungen ein."
            objectWillChange.send() // Schalter zurücksetzen
            return
        }
        enabled = on
        UserDefaults.standard.set(on, forKey: "lock")
    }

    /// Nach mehr als 60 Sekunden im Hintergrund wird die App wieder gesperrt.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            if enabled, !locked, let t = backgroundedAt, Date().timeIntervalSince(t) > 60 {
                locked = true
                autoPrompt = true
            }
            backgroundedAt = nil
            promptIfNeeded()
        default:
            break
        }
    }

    func promptIfNeeded() {
        guard locked && autoPrompt else { return }
        autoPrompt = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.authenticate() }
    }

    func authenticate() {
        guard !authRunning else { return }
        guard canAuthenticate else {
            // Gerätecode wurde in den Einstellungen entfernt
            locked = false
            return
        }
        authRunning = true
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Eben-Ezer entsperren – deine Zeugnisse sind geschützt") { success, _ in
            DispatchQueue.main.async {
                self.authRunning = false
                if success {
                    withAnimation(.easeOut(duration: 0.25)) { self.locked = false }
                }
            }
        }
    }
}

struct LockView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Color.green800.ignoresSafeArea()
            VStack(spacing: 0) {
                StonesLogo(size: 96)
                Text("Eben-Ezer")
                    .font(TS.display)
                    .kerning(-1.2)
                    .foregroundColor(.offWhite)
                    .padding(.top, 20)
                Tagline(size: 30, serifColor: .gold100, sansColor: .gold400)
                    .padding(.top, 2)
                Text("Bis hierher hat uns der HERR geholfen.")
                    .font(TS.bodyL)
                    .foregroundColor(.blue400)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                Button {
                    lock.authenticate()
                } label: {
                    Label("Entsperren", systemImage: "faceid")
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 40)
            }
            .padding(32)
        }
        .onAppear { lock.promptIfNeeded() }
    }
}

private struct LockCover: ViewModifier {
    @ObservedObject var lock: AppLock

    func body(content: Content) -> some View {
        ZStack {
            content
            if lock.locked {
                LockView(lock: lock)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

extension View {
    /// Legt den Sperrbildschirm über diese Ansicht, solange die App gesperrt ist.
    func lockCover(_ lock: AppLock) -> some View { modifier(LockCover(lock: lock)) }
}
