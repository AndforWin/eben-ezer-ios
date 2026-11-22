//
//  Share.swift
//  Eben-Ezer
//
//  Teilen als Text oder als gestaltete Bild-Karte im GEC-Design.
//

import SwiftUI
import UIKit

enum ShareMode {
    case card, text, cardWithMedia
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum Sharer {
    static func text(_ t: Testimony) -> String {
        var s = "✨ \(t.title)\n📅 \(formatDate(t.date))"
        if !t.persons.isBlank { s += "  ·  👥 \(t.persons)" }
        s += "\n"
        if !t.situation.isBlank { s += "\nDie Situation:\n\(t.situation.trimmed)\n" }
        if !t.godDid.isBlank { s += "\n🙌 Was Gott getan hat:\n\(t.godDid.trimmed)\n" }
        if !t.verse.isBlank { s += "\n📖 \(t.verse.trimmed)\n" }
        s += "\n„Bis hierher hat uns der HERR geholfen.“ – 1. Samuel 7,12"
        return s
    }

    @MainActor
    static func items(for t: Testimony, mode: ShareMode, media: MediaFiles) throws -> [Any] {
        if mode == .text { return [text(t)] }
        var items: [Any] = [try renderCard(t)]
        if mode == .cardWithMedia {
            for a in t.attachments {
                let url = media.url(a)
                if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
            }
        }
        return items
    }

    @MainActor
    static func renderCard(_ t: Testimony) throws -> URL {
        let renderer = ImageRenderer(content: ShareCard(t: t))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Zeugnis_\(DayFormat.string(t.date))_\(t.id.prefix(6)).png")
        try data.write(to: url)
        return url
    }
}

private func clip(_ s: String, _ max: Int) -> String {
    let t = s.trimmed
    guard t.count > max else { return t }
    return String(t.prefix(max)).trimmingCharacters(in: .whitespaces) + " …"
}

/// Bild-Karte, 1080 Pixel breit (wie in der Android-App).
struct ShareCard: View {
    let t: Testimony
    private let pad: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kopfbereich (grün)
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("EBEN-EZER")
                        .font(.system(size: 30, weight: .bold))
                        .kerning(3.6)
                        .foregroundColor(.gold400)
                    Tagline(size: 46, serifColor: .gold100, sansColor: .gold400)
                        .padding(.top, 6)
                    Text(formatDate(t.date))
                        .font(.system(size: 34))
                        .foregroundColor(.blue400)
                        .padding(.top, 36)
                    Text(clip(t.title, 200))
                        .font(.system(size: 76, weight: .bold))
                        .kerning(-1.5)
                        .foregroundColor(.offWhite)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StonesLogo(size: 110)
                    .padding(.top, -26)
            }
            .padding(.horizontal, pad)
            .padding(.top, 96)
            .padding(.bottom, 84)
            .background(Color.green800)

            VStack(alignment: .leading, spacing: 56) {
                labelled("Beteiligte Personen", t.persons, boxed: false)
                labelled("Die Situation", t.situation, boxed: false)
                labelled("Was Gott getan hat", t.godDid, boxed: true)
                if !t.verse.isBlank {
                    Text(clip(t.verse, 500))
                        .font(.system(size: 40, weight: .bold).italic())
                        .foregroundColor(.green800)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.gold400).frame(width: 8)
                        }
                }
                if !t.categories.isEmpty {
                    Text(t.categories.joined(separator: "  ·  "))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.green800)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 36) {
                    Rectangle().fill(Color.gold400).frame(height: 3)
                    Text("„Bis hierher hat uns der HERR geholfen.“  1. Samuel 7,12")
                        .font(.system(size: 30).italic())
                        .foregroundColor(.green800)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, pad)
            .padding(.top, 64)
            .padding(.bottom, 84)
        }
        .frame(width: 1080)
        .background(Color.offWhite)
    }

    @ViewBuilder
    private func labelled(_ label: String, _ text: String, boxed: Bool) -> some View {
        if !text.isBlank {
            VStack(alignment: .leading, spacing: 16) {
                Text(label.uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .kerning(2.8)
                    .foregroundColor(.gold800)
                Text(clip(text, 1400))
                    .font(.system(size: 40))
                    .lineSpacing(10)
                    .foregroundColor(.offBlack)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(boxed ? 48 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if boxed {
                    RoundedRectangle(cornerRadius: 40)
                        .fill(Color.gold100)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.gold400).frame(width: 12)
                        }
                }
            }
        }
    }
}
