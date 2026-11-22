//
//  Model.swift
//  Eben-Ezer
//
//  Datenmodell – identisch zum JSON-Format der Android-App,
//  damit Sicherungen zwischen Android und iPhone austauschbar sind.
//

import Foundation

enum MediaType: String, Codable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
}

struct Attachment: Identifiable, Hashable, Codable {
    var id: String
    var type: MediaType
    var fileName: String
    var label: String

    init(id: String = UUID().uuidString.lowercased(), type: MediaType, fileName: String, label: String = "") {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id, type, label
        case fileName = "file"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(MediaType.self, forKey: .type)
        fileName = try c.decode(String.self, forKey: .fileName)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

struct Testimony: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString.lowercased()
    var date: Date = Calendar.current.startOfDay(for: Date())
    var title = ""
    var persons = ""
    var situation = ""
    var godDid = ""
    var verse = ""
    var categories: [String] = []
    var attachments: [Attachment] = []
    var favorite = false
    var createdAt: Int64 = nowMillis()
    var updatedAt: Int64 = nowMillis()

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, date, title, persons, situation, godDid, verse, categories, attachments, favorite, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let dateString = try c.decode(String.self, forKey: .date)
        guard let d = DayFormat.parse(dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Ungültiges Datum: \(dateString)")
        }
        date = d
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        persons = try c.decodeIfPresent(String.self, forKey: .persons) ?? ""
        situation = try c.decodeIfPresent(String.self, forKey: .situation) ?? ""
        godDid = try c.decodeIfPresent(String.self, forKey: .godDid) ?? ""
        verse = try c.decodeIfPresent(String.self, forKey: .verse) ?? ""
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? nowMillis()
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? nowMillis()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(DayFormat.string(date), forKey: .date)
        try c.encode(title, forKey: .title)
        try c.encode(persons, forKey: .persons)
        try c.encode(situation, forKey: .situation)
        try c.encode(godDid, forKey: .godDid)
        try c.encode(verse, forKey: .verse)
        try c.encode(categories, forKey: .categories)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(favorite, forKey: .favorite)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

let defaultCategories = [
    "Gebetserhörung", "Heilung", "Versorgung", "Führung", "Bewahrung",
    "Befreiung", "Beziehungen", "Familie", "Arbeit & Finanzen", "Gemeinde", "Wunder",
]

// MARK: - Datum

enum DayFormat {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()

    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func parse(_ s: String) -> Date? { iso.date(from: s) }
    static func long(_ d: Date) -> String { longFormatter.string(from: d) }
}

func formatDate(_ d: Date) -> String { DayFormat.long(d) }

// MARK: - Hilfen

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private let german = Locale(identifier: "de_DE")

extension Testimony {
    func matches(_ query: String) -> Bool {
        let words = query.lowercased(with: german).split(whereSeparator: { $0.isWhitespace })
        if words.isEmpty { return true }
        let hay = [title, persons, situation, godDid, verse, categories.joined(separator: " "), formatDate(date)]
            .joined(separator: "\n")
            .lowercased(with: german)
        return words.allSatisfy { hay.contains($0) }
    }

    var year: Int { Calendar.current.component(.year, from: date) }

    /// Kurzer Vorschautext: „Was hat Gott getan?“, sonst die Situation.
    var snippet: String { godDid.isBlank ? situation : godDid }

    var displayTitle: String { title.isBlank ? "Ohne Überschrift" : title }
}

// MARK: - JSON (Sicherungsformat der Android-App)

private struct BackupOut: Encodable {
    let app = "Eben-Ezer"
    let version = 1
    let entries: [Testimony]
}

private struct BackupIn: Decodable {
    let entries: [Testimony]
}

func entriesToJSON(_ list: [Testimony]) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    return try enc.encode(BackupOut(entries: list))
}

func entriesFromJSON(_ data: Data) throws -> [Testimony] {
    try JSONDecoder().decode(BackupIn.self, from: data).entries
}

enum BackupError: LocalizedError {
    case invalid
    var errorDescription: String? { "Keine gültige Eben-Ezer-Sicherung" }
}
