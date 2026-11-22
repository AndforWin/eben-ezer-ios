//
//  SettingsView.swift
//  Eben-Ezer
//
//  Statistik, App-Sperre, Sicherung und Infos.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var lock: AppLock

    @State private var shareItems: ShareItems?
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                stats

                card("Datenschutz") {
                    HStack(spacing: 12) {
                        Image(systemName: "faceid")
                            .font(.system(size: 22))
                            .foregroundColor(.green800)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App-Sperre")
                                .font(TS.titleM)
                                .foregroundColor(.green800)
                            Text("Mit Face ID, Touch ID oder Gerätecode entsperren")
                                .font(TS.bodyM)
                                .foregroundColor(.gray700)
                        }
                        Spacer()
                        Toggle("App-Sperre", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                            .labelsHidden()
                            .tint(.green800)
                    }
                    .messageAlert($lock.message)
                }

                card("Sicherung") {
                    Text("Alle Zeugnisse inklusive Fotos, Videos und Audios als ZIP-Datei speichern – z. B. in iCloud Drive, Google Drive oder auf dem PC. So kannst du sie auf einem neuen Handy wiederherstellen – auch zwischen Android und iPhone.")
                        .font(TS.bodyM)
                        .foregroundColor(.gray700)
                    Button { exportBackup() } label: {
                        Label("Sicherung erstellen", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PillButtonStyle(fullWidth: true))
                    .disabled(store.busy)
                    .padding(.top, 12)
                    Button { showImporter = true } label: {
                        Label("Sicherung wiederherstellen", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(OutlinePillStyle(fullWidth: true))
                    .disabled(store.busy)
                    .padding(.top, 8)
                    if store.busy {
                        ProgressView()
                            .tint(.gold400)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                }

                about
            }
            .padding(20)
        }
        .background(Color.offWhite.ignoresSafeArea())
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offWhite, for: .navigationBar)
        .sheet(item: $shareItems) { items in
            ShareSheet(items: items.items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            importBackup(result)
        }
        .messageAlert($message)
    }

    // MARK: Bausteine

    private var stats: some View {
        HStack {
            stat("\(store.entries.count)", "Zeugnisse")
            stat("\(store.entries.filter(\.favorite).count)", "Favoriten")
            stat("\(store.entries.reduce(0) { $0 + $1.attachments.count })", "Anhänge")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.green800))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(TS.headlineM).foregroundColor(.gold400)
            Text(label).font(TS.labelM).foregroundColor(.offWhite)
        }
        .frame(maxWidth: .infinity)
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Overline(text: title).padding(.bottom, 12)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
    }

    private var about: some View {
        VStack(spacing: 0) {
            StonesLogo(size: 56)
            Text("Eben-Ezer")
                .font(TS.headlineS)
                .foregroundColor(.green800)
                .padding(.top, 8)
            Tagline(size: 20)
            Text("„Da nahm Samuel einen Stein … und nannte ihn Eben-Ezer und sprach: Bis hierher hat uns der HERR geholfen.“")
                .font(TS.bodyM.italic())
                .foregroundColor(.gray700)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            Text("1. Samuel 7,12")
                .font(TS.labelM)
                .foregroundColor(.gold800)
                .padding(.top, 4)
            Text(verbatim: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1")")
                .font(TS.labelS)
                .foregroundColor(.gray500)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: Sicherung

    private func exportBackup() {
        Task {
            do {
                let url = try await store.makeBackup()
                await MainActor.run { shareItems = ShareItems(items: [url]) }
            } catch {
                let text = "Sicherung fehlgeschlagen: \(error.localizedDescription)"
                await MainActor.run { message = text }
            }
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            do {
                let n = try await store.restoreBackup(from: url)
                await MainActor.run { message = n == 1 ? "1 Zeugnis wiederhergestellt" : "\(n) Zeugnisse wiederhergestellt" }
            } catch {
                let text = "Import fehlgeschlagen: \(error.localizedDescription)"
                await MainActor.run { message = text }
            }
        }
    }
}
