//
//  Store.swift
//  Eben-Ezer
//
//  Hält alle Zeugnisse, speichert sie und steuert die Navigation
//  (entspricht MainViewModel + Repository der Android-App).
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum Route: Hashable {
    case detail(String)
    case settings
}

struct EditTarget: Identifiable {
    let id = UUID()
    let testimonyID: String?
}

// MARK: - Mediendateien

struct MediaFiles {
    let dir: URL

    func url(_ a: Attachment) -> URL { dir.appendingPathComponent(a.fileName) }

    func newURL(ext: String) -> URL {
        dir.appendingPathComponent("\(UUID().uuidString.lowercased()).\(ext)")
    }

    /// Kopiert (oder verschiebt) eine Datei in den App-Speicher.
    func importFile(_ src: URL, type: MediaType, label: String, move: Bool = false) throws -> Attachment {
        var ext = src.pathExtension.lowercased()
        if ext.isEmpty {
            switch type {
            case .image: ext = "jpg"
            case .video: ext = "mp4"
            case .audio: ext = "m4a"
            }
        }
        let dest = newURL(ext: ext)
        if move {
            try FileManager.default.moveItem(at: src, to: dest)
        } else {
            try FileManager.default.copyItem(at: src, to: dest)
        }
        return Attachment(type: type, fileName: dest.lastPathComponent, label: label)
    }

    /// Speichert ein Foto als JPEG (lesbar auf iPhone und Android).
    func saveImage(_ image: UIImage, label: String) throws -> Attachment {
        guard let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        let dest = newURL(ext: "jpg")
        try data.write(to: dest, options: .atomic)
        return Attachment(type: .image, fileName: dest.lastPathComponent, label: label)
    }

    /// Übernimmt ein Foto oder Video aus der Fotomediathek.
    func importPicked(_ item: PhotosPickerItem) async -> Attachment? {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        do {
            if isVideo {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return nil }
                return try importFile(movie.url, type: .video, label: "Video", move: true)
            } else {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return nil }
                return try saveImage(image, label: "Foto")
            }
        } catch {
            return nil
        }
    }
}

/// Video aus der Fotomediathek als Datei übernehmen.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published private(set) var entries: [Testimony] = []
    @Published var query = ""
    @Published var categoryFilter: String?
    @Published var favoritesOnly = false
    @Published var path: [Route] = []
    @Published var editing: EditTarget?
    @Published var busy = false

    let media: MediaFiles
    private let baseDir: URL
    private let dataFile: URL
    private let ioQueue = DispatchQueue(label: "de.gechn.ebenezer.io")

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("EbenEzer", isDirectory: true)
        dataFile = baseDir.appendingPathComponent("testimonies.json")
        let mediaDir = baseDir.appendingPathComponent("media", isDirectory: true)
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        media = MediaFiles(dir: mediaDir)
        entries = Store.sorted(Store.load(from: dataFile, baseDir: baseDir))
    }

    private static func load(from file: URL, baseDir: URL) -> [Testimony] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        do {
            return try entriesFromJSON(data)
        } catch {
            // Beschädigte Datei sichern, statt sie später zu überschreiben
            let backup = baseDir.appendingPathComponent("testimonies.corrupt-\(nowMillis()).json")
            try? FileManager.default.copyItem(at: file, to: backup)
            return []
        }
    }

    private static func sorted(_ list: [Testimony]) -> [Testimony] {
        list.sorted { a, b in
            a.date != b.date ? a.date > b.date : a.createdAt > b.createdAt
        }
    }

    private func setAndSave(_ list: [Testimony]) {
        entries = Store.sorted(list)
        guard let data = try? entriesToJSON(entries) else { return }
        let url = dataFile
        ioQueue.async { try? data.write(to: url, options: .atomic) }
    }

    private func deleteFiles(_ atts: [Attachment]) {
        let urls = atts.map(media.url)
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    // MARK: Abfragen

    func get(_ id: String) -> Testimony? { entries.first { $0.id == id } }

    var isFiltering: Bool { !query.isBlank || categoryFilter != nil || favoritesOnly }

    var filtered: [Testimony] {
        entries.filter { t in
            t.matches(query)
                && (categoryFilter.map { t.categories.contains($0) } ?? true)
                && (!favoritesOnly || t.favorite)
        }
    }

    var usedCategories: [String] {
        let used = Set(entries.flatMap(\.categories))
        return defaultCategories.filter { used.contains($0) }
            + used.filter { !defaultCategories.contains($0) }.sorted()
    }

    var allCategories: [String] {
        let extra = Set(entries.flatMap(\.categories)).filter { !defaultCategories.contains($0) }.sorted()
        return defaultCategories + extra
    }

    func onThisDay(_ today: Date = Date()) -> [Testimony] {
        let cal = Calendar.current
        let now = cal.dateComponents([.year, .month, .day], from: today)
        return entries.filter {
            let c = cal.dateComponents([.year, .month, .day], from: $0.date)
            return c.month == now.month && c.day == now.day && (c.year ?? 0) < (now.year ?? 0)
        }
    }

    // MARK: Navigation

    func open(_ id: String) { path.append(.detail(id)) }
    func openSettings() { path.append(.settings) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func openRandom() { if let t = entries.randomElement() { open(t.id) } }
    func startEdit(_ id: String?) { editing = EditTarget(testimonyID: id) }

    // MARK: Ändern

    func toggleFavorite(_ t: Testimony) {
        var c = t
        c.favorite.toggle()
        upsert(c)
    }

    func delete(_ t: Testimony) {
        setAndSave(entries.filter { $0.id != t.id })
        deleteFiles(t.attachments)
    }

    private func upsert(_ t: Testimony) {
        var c = t
        c.updatedAt = nowMillis()
        setAndSave(entries.filter { $0.id != t.id } + [c])
    }

    /// Speichert einen Entwurf und räumt nicht mehr benötigte Dateien auf.
    func saveDraft(_ draft: Testimony, original: Testimony?, added: [Attachment]) {
        var d = draft
        d.title = d.title.trimmed
        let keep = Set(d.attachments)
        let obsolete = ((original?.attachments ?? []) + added).filter { !keep.contains($0) }
        upsert(d)
        deleteFiles(obsolete)
    }

    /// Verwirft einen Entwurf und löscht neu hinzugefügte Dateien.
    func cancelDraft(added: [Attachment]) { deleteFiles(added) }

    // MARK: Sicherung (ZIP, kompatibel mit der Android-App)

    @MainActor
    func makeBackup() async throws -> URL {
        let snapshot = entries
        let media = self.media
        busy = true
        defer { busy = false }
        return try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let json = try entriesToJSON(snapshot)
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("Eben-Ezer-Sicherung-\(DayFormat.string(Date())).zip")
            try? FileManager.default.removeItem(at: out)
            let zip = try ZipWriter(url: out)
            try zip.add(name: "testimonies.json", data: json)
            for a in snapshot.flatMap(\.attachments) {
                let f = media.url(a)
                if FileManager.default.fileExists(atPath: f.path) {
                    try zip.add(name: "media/\(a.fileName)", data: try Data(contentsOf: f, options: .mappedIfSafe))
                }
            }
            try zip.finish()
            return out
        }.value
    }

    @MainActor
    func restoreBackup(from url: URL) async throws -> Int {
        let media = self.media
        busy = true
        defer { busy = false }
        let imported: [Testimony] = try await Task.detached(priority: .userInitiated) { () throws -> [Testimony] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let reader = try ZipReader(url: url)
            var json: Data?
            for e in reader.entries where !e.isDirectory {
                if e.name == "testimonies.json" {
                    json = try reader.extract(e)
                } else if e.name.hasPrefix("media/") {
                    let name = (e.name as NSString).lastPathComponent // nur Dateiname, keine Pfade
                    if !name.isEmpty && name != "." && name != ".." {
                        try reader.extract(e).write(to: media.dir.appendingPathComponent(name), options: .atomic)
                    }
                }
            }
            guard let json = json else { throw BackupError.invalid }
            return try entriesFromJSON(json)
        }.value
        var map: [String: Testimony] = [:]
        for t in entries { map[t.id] = t }
        for t in imported { map[t.id] = t }
        setAndSave(Array(map.values))
        return imported.count
    }
}
