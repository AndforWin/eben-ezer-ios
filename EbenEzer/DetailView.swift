//
//  DetailView.swift
//  Eben-Ezer
//
//  Ein Zeugnis ansehen, teilen, bearbeiten oder löschen.
//

import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: Store
    let id: String

    @State private var confirmDelete = false
    @State private var showShareOptions = false
    @State private var shareItems: ShareItems?
    @State private var viewer: MediaViewerItem?
    @State private var message: String?

    var body: some View {
        if let t = store.get(id) {
            content(t)
        } else {
            Color.offWhite.ignoresSafeArea()
        }
    }

    private func content(_ t: Testimony) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    Overline(text: formatDate(t.date))
                    Text(t.displayTitle)
                        .font(TS.display)
                        .kerning(-1.2)
                        .foregroundColor(.green800)
                        .padding(.top, 6)
                        .textSelection(.enabled)
                    if !t.categories.isEmpty {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(t.categories, id: \.self) { CategoryPill(text: $0) }
                        }
                        .padding(.top, 12)
                    }
                }

                if !t.persons.isBlank {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill").foregroundColor(.gold800)
                        Text(t.persons).font(TS.bodyL).foregroundColor(.offBlack)
                    }
                }

                if !t.situation.isBlank {
                    LabeledSection(label: "Was war das Problem / die Situation?") {
                        Text(t.situation)
                            .font(TS.bodyL)
                            .foregroundColor(.offBlack)
                            .textSelection(.enabled)
                    }
                }

                if !t.godDid.isBlank {
                    LabeledSection(label: "Was hat Gott getan?") {
                        Text(t.godDid)
                            .font(TS.bodyL)
                            .foregroundColor(.offBlack)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.gold100))
                }

                if !t.verse.isBlank {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "book.fill").foregroundColor(.gold400)
                        Text(t.verse)
                            .font(TS.bodyL.italic())
                            .foregroundColor(.offWhite)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.green800))
                }

                attachments(t)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color.offWhite.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.offWhite, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { store.toggleFavorite(t) } label: {
                    Image(systemName: t.favorite ? "star.fill" : "star").foregroundColor(.gold800)
                }
                .accessibilityLabel(t.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
                Button { showShareOptions = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Teilen")
                Button { store.startEdit(t.id) } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Bearbeiten")
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Löschen")
            }
        }
        .confirmationDialog("Zeugnis teilen", isPresented: $showShareOptions, titleVisibility: .visible) {
            Button("Als Bild-Karte") { share(t, .card) }
            Button("Als Text") { share(t, .text) }
            if !t.attachments.isEmpty {
                Button("Bild-Karte + Anhänge (\(t.attachments.count))") { share(t, .cardWithMedia) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bild-Karte: schön gestaltet – ideal für WhatsApp, Signal oder die Instagram-Story.")
        }
        .alert("Zeugnis löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                store.pop()
                store.delete(t)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("„\(t.title)“ und alle Anhänge werden endgültig gelöscht.")
        }
        .sheet(item: $shareItems) { items in
            ShareSheet(items: items.items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewer) { MediaViewer(item: $0) }
        .messageAlert($message)
    }

    @ViewBuilder
    private func attachments(_ t: Testimony) -> some View {
        if !t.attachments.isEmpty {
            LabeledSection(label: "Anhänge") {
                let visuals = t.attachments.filter { $0.type != .audio }
                if !visuals.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(visuals) { a in
                            Button {
                                viewer = MediaViewerItem(url: store.media.url(a), type: a.type)
                            } label: {
                                MediaThumb(url: store.media.url(a), type: a.type, size: 104)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(t.attachments.filter { $0.type == .audio }) { a in
                    AudioPlayerView(url: store.media.url(a), label: a.label)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func share(_ t: Testimony, _ mode: ShareMode) {
        let media = store.media
        // kurz warten, bis das Auswahlmenü geschlossen ist
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            do {
                shareItems = ShareItems(items: try Sharer.items(for: t, mode: mode, media: media))
            } catch {
                message = "Teilen ist leider fehlgeschlagen."
            }
        }
    }
}
