//
//  EditView.swift
//  Eben-Ezer
//
//  Neues Zeugnis anlegen oder bearbeiten – mit Fotos, Videos und Sprachaufnahmen.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditView: View {
    @EnvironmentObject private var store: Store
    let original: Testimony?

    @State private var draft: Testimony
    @State private var initial: Testimony
    @State private var added: [Attachment] = []

    @State private var titleError = false
    @State private var confirmDiscard = false
    @State private var camera: CameraPicker.Mode?
    @State private var showRecorder = false
    @State private var showAudioImporter = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var addCategory = false
    @State private var newCategory = ""
    @State private var notice: String?
    @State private var viewer: MediaViewerItem?

    init(original: Testimony?) {
        self.original = original
        let d = original ?? Testimony()
        _draft = State(initialValue: d)
        _initial = State(initialValue: d)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dateRow

                    VStack(alignment: .leading, spacing: 6) {
                        field("Überschrift *", text: $draft.title, single: true, error: titleError)
                        if titleError {
                            Text("Bitte gib eine Überschrift ein.")
                                .font(TS.labelS)
                                .foregroundColor(.red800)
                        }
                    }
                    field("Beteiligte Personen", text: $draft.persons, single: true, words: true)
                    field("Was war das Problem / die Situation?", text: $draft.situation, minLines: 3)
                    field("Was hat Gott getan?", text: $draft.godDid, minLines: 4, highlight: true)
                    field("Bibelvers (optional)", text: $draft.verse, minLines: 2,
                          placeholder: "z. B. Psalm 103,2 – Lobe den HERRN, meine Seele …")

                    categories
                    attachmentsSection

                    Button("Speichern") { save() }
                        .buttonStyle(PillButtonStyle(fullWidth: true))
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.offWhite.ignoresSafeArea())
            .messageAlert($notice)
            .fullScreenCover(item: $viewer) { MediaViewer(item: $0) }
            .navigationTitle(original == nil ? "Neues Zeugnis" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.offWhite, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schließen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .font(TS.labelL)
                }
            }
        }
        .onChange(of: draft.title) { _ in titleError = false }
        .onChange(of: pickerItems) { items in importPicked(items) }
        .fullScreenCover(item: $camera) { mode in
            CameraPicker(mode: mode) { image, url in handleCamera(mode, image, url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showRecorder) {
            RecorderSheet(media: store.media) { att in
                showRecorder = false
                if let att = att { addAttachments([att]) }
            }
            .presentationDetents([.medium])
        }
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            importAudio(result)
        }
        .alert("Änderungen verwerfen?", isPresented: $confirmDiscard) {
            Button("Verwerfen", role: .destructive) { cancel() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Deine Eingaben gehen verloren.")
        }
    }

    // MARK: Felder

    private var dateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").foregroundColor(.green800)
            DatePicker("Datum", selection: $draft.date, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
            Spacer()
        }
    }

    private func field(_ label: String, text: Binding<String>, minLines: Int = 1, single: Bool = false,
                       error: Bool = false, highlight: Bool = false, placeholder: String? = nil,
                       words: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TS.labelM)
                .foregroundColor(error ? .red800 : .green800)
            Group {
                if single {
                    TextField(placeholder ?? "", text: text)
                } else {
                    TextField(placeholder ?? "", text: text, axis: .vertical)
                        .lineLimit(minLines...)
                }
            }
            .font(TS.bodyL)
            .foregroundColor(.offBlack)
            .textInputAutocapitalization(words ? TextInputAutocapitalization.words : TextInputAutocapitalization.sentences)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(highlight ? Color.gold100 : Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(error ? Color.red800 : (highlight ? Color.gold400 : Color.gray300), lineWidth: error ? 2 : 1)
            )
        }
    }

    // MARK: Kategorien

    private var allCategories: [String] {
        var seen = Set<String>()
        return (store.allCategories + draft.categories).filter { seen.insert($0).inserted }
    }

    private var categories: some View {
        LabeledSection(label: "Kategorien") {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(allCategories, id: \.self) { c in
                    let selected = draft.categories.contains(c)
                    Chip(label: c, selected: selected, icon: selected ? "checkmark" : nil) {
                        if selected {
                            draft.categories.removeAll { $0 == c }
                        } else {
                            draft.categories.append(c)
                        }
                    }
                }
                Chip(label: "Eigene", selected: false, icon: "plus") {
                    newCategory = ""
                    addCategory = true
                }
            }
        }
        .alert("Eigene Kategorie", isPresented: $addCategory) {
            TextField("z. B. Studium", text: $newCategory)
            Button("Hinzufügen") {
                let name = newCategory.trimmed
                if !name.isEmpty && !draft.categories.contains(name) { draft.categories.append(name) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Anhänge

    private var attachmentsSection: some View {
        LabeledSection(label: "Anhänge") {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    AddLabel(icon: "photo.on.rectangle", text: "Galerie")
                }
                Button { openCamera(.photo) } label: { AddLabel(icon: "camera", text: "Foto") }
                Button { openCamera(.video) } label: { AddLabel(icon: "video", text: "Video") }
                Button { showRecorder = true } label: { AddLabel(icon: "mic", text: "Aufnehmen") }
                Button { showAudioImporter = true } label: { AddLabel(icon: "waveform", text: "Audio-Datei") }
            }
            .buttonStyle(.plain)

            if importing {
                ProgressView("Anhänge werden übernommen …")
                    .font(TS.bodyM)
                    .tint(.gold400)
                    .padding(.top, 8)
            }

            let visuals = draft.attachments.filter { $0.type != .audio }
            if !visuals.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(visuals) { a in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                viewer = MediaViewerItem(url: store.media.url(a), type: a.type)
                            } label: {
                                MediaThumb(url: store.media.url(a), type: a.type, size: 96)
                            }
                            .buttonStyle(.plain)
                            Button { remove(a) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.offBlack.opacity(0.7)))
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .accessibilityLabel("Entfernen")
                        }
                    }
                }
                .padding(.top, 8)
            }

            ForEach(draft.attachments.filter { $0.type == .audio }) { a in
                AudioPlayerView(url: store.media.url(a), label: a.label) {
                    Button { remove(a) } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray700)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Entfernen")
                }
                .padding(.top, 8)
            }
        }
    }

    private func addAttachments(_ atts: [Attachment]) {
        added += atts
        draft.attachments += atts
    }

    private func remove(_ a: Attachment) {
        draft.attachments.removeAll { $0 == a }
    }

    private func openCamera(_ mode: CameraPicker.Mode) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            camera = mode
        } else {
            notice = "Auf diesem Gerät ist keine Kamera verfügbar."
        }
    }

    private func handleCamera(_ mode: CameraPicker.Mode, _ image: UIImage?, _ url: URL?) {
        camera = nil
        do {
            if mode == .photo, let image = image {
                addAttachments([try store.media.saveImage(image, label: "Foto")])
            } else if mode == .video, let url = url {
                addAttachments([try store.media.importFile(url, type: .video, label: "Video")])
            }
        } catch {
            notice = "Die Aufnahme konnte nicht gespeichert werden."
        }
    }

    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickerItems = []
        importing = true
        let media = store.media
        Task {
            var atts: [Attachment] = []
            for item in items {
                if let a = await media.importPicked(item) { atts.append(a) }
            }
            let imported = atts
            await MainActor.run {
                importing = false
                addAttachments(imported)
                if imported.count < items.count {
                    notice = "\(items.count - imported.count) Datei(en) konnten nicht übernommen werden."
                }
            }
        }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var atts: [Attachment] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let a = try? store.media.importFile(url, type: .audio, label: url.lastPathComponent) {
                atts.append(a)
            }
        }
        addAttachments(atts)
        if atts.count < urls.count {
            notice = "\(urls.count - atts.count) Datei(en) konnten nicht übernommen werden."
        }
    }

    // MARK: Speichern / Verwerfen

    private func save() {
        if draft.title.isBlank {
            titleError = true
            notice = "Bitte gib eine Überschrift ein."
            return
        }
        if importing {
            notice = "Anhänge werden noch kopiert …"
            return
        }
        store.saveDraft(draft, original: original, added: added)
        store.editing = nil
    }

    private func close() {
        if draft != initial { confirmDiscard = true } else { cancel() }
    }

    private func cancel() {
        store.cancelDraft(added: added)
        store.editing = nil
    }
}

private struct AddLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 15, weight: .medium))
        }
        .foregroundColor(.green800)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color.gray300, lineWidth: 1))
        .contentShape(Capsule())
    }
}
