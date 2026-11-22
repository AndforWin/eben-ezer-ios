//
//  HomeView.swift
//  Eben-Ezer
//
//  Startseite: Suche, Filter, „Heute vor … Jahren“ und alle Zeugnisse nach Jahren.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let list = store.filtered
        let filtering = store.isFiltering

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header

                if !store.entries.isEmpty {
                    Text(verbatim: store.entries.count == 1 ? "1 Zeugnis festgehalten" : "\(store.entries.count) Zeugnisse festgehalten")
                        .font(TS.bodyM)
                        .foregroundColor(.gray700)
                        .padding(.leading, 4)
                    SearchField(text: $store.query)
                    FilterRow()
                }

                if !filtering {
                    ForEach(store.onThisDay()) { t in
                        OnThisDayCard(t: t) { store.open(t.id) }
                    }
                }

                if store.entries.isEmpty {
                    EmptyState { store.startEdit(nil) }
                } else if list.isEmpty && filtering {
                    Text("Nichts gefunden.")
                        .font(TS.bodyL)
                        .foregroundColor(.gray700)
                        .frame(maxWidth: .infinity)
                        .padding(32)
                }

                ForEach(groupedByYear(list), id: \.year) { group in
                    Text(verbatim: String(group.year))
                        .font(TS.headlineS)
                        .foregroundColor(.green800)
                        .padding(.leading, 4)
                        .padding(.top, 12)
                    ForEach(group.items) { t in
                        Button { store.open(t.id) } label: { TestimonyCard(t: t) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.offWhite.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) { addButton }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            StonesLogo(size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("Eben-Ezer")
                    .font(TS.headlineM)
                    .kerning(-1)
                    .foregroundColor(.green800)
                Tagline(size: 17)
            }
            Spacer()
            Button { store.openRandom() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.green800)
                    .frame(width: 44, height: 44)
            }
            .disabled(store.entries.isEmpty)
            .opacity(store.entries.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Zufälliges Zeugnis")
            Button { store.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.green800)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Einstellungen")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var addButton: some View {
        Button { store.startEdit(nil) } label: {
            Label("Zeugnis", systemImage: "plus")
                .font(TS.labelL)
                .foregroundColor(.offBlack)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 23).fill(Color.gold400))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Gruppierung

struct YearGroup {
    let year: Int
    var items: [Testimony]
}

func groupedByYear(_ list: [Testimony]) -> [YearGroup] {
    var out: [YearGroup] = []
    for t in list {
        if let last = out.last, last.year == t.year {
            out[out.count - 1].items.append(t)
        } else {
            out.append(YearGroup(year: t.year, items: [t]))
        }
    }
    return out
}

// MARK: - Bausteine der Startseite

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.green800)
            TextField("Suchen – Name, Situation, Vers …", text: $text)
                .font(TS.bodyL)
                .foregroundColor(.offBlack)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray500)
                }
                .accessibilityLabel("Leeren")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 23).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.outlineSoft, lineWidth: 1.5))
    }
}

struct FilterRow: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(label: "Favoriten", selected: store.favoritesOnly, icon: "star.fill", iconColor: .gold400) {
                    store.favoritesOnly.toggle()
                }
                ForEach(store.usedCategories, id: \.self) { c in
                    Chip(label: c, selected: store.categoryFilter == c) {
                        store.categoryFilter = store.categoryFilter == c ? nil : c
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }
}

struct OnThisDayCard: View {
    let t: Testimony
    let action: () -> Void

    var body: some View {
        let years = Calendar.current.component(.year, from: Date()) - t.year
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Overline(text: years == 1 ? "Heute vor einem Jahr" : "Heute vor \(years) Jahren", color: .gold400)
                Text(t.displayTitle)
                    .font(TS.titleL)
                    .foregroundColor(.offWhite)
                    .multilineTextAlignment(.leading)
                if !t.snippet.isBlank {
                    Text(t.snippet)
                        .font(TS.bodyM)
                        .foregroundColor(.blue400)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.green800))
        }
        .buttonStyle(.plain)
    }
}

struct TestimonyCard: View {
    @EnvironmentObject private var store: Store
    let t: Testimony

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Overline(text: formatDate(t.date))
                    Spacer()
                    if t.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.gold400)
                            .accessibilityLabel("Favorit")
                    }
                }
                Text(t.displayTitle)
                    .font(TS.titleL)
                    .foregroundColor(.green800)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
                if !t.snippet.isBlank {
                    Text(t.snippet)
                        .font(TS.bodyM)
                        .foregroundColor(.offBlack)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }
                if !t.categories.isEmpty || !t.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(t.categories.prefix(2)), id: \.self) { CategoryPill(text: $0) }
                        if t.categories.count > 2 {
                            Text(verbatim: "+\(t.categories.count - 2)")
                                .font(TS.labelS)
                                .foregroundColor(.gray500)
                        }
                        MediaCount(icon: "photo", n: count(.image))
                        MediaCount(icon: "video.fill", n: count(.video))
                        MediaCount(icon: "waveform", n: count(.audio))
                    }
                    .padding(.top, 10)
                }
            }
            if let visual = t.attachments.first(where: { $0.type != .audio }) {
                MediaThumb(url: store.media.url(visual), type: visual.type, size: 72)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gold100, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private func count(_ type: MediaType) -> Int { t.attachments.filter { $0.type == type }.count }
}

struct MediaCount: View {
    let icon: String
    let n: Int

    var body: some View {
        if n > 0 {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 12))
                Text(verbatim: "\(n)").font(TS.labelS)
            }
            .foregroundColor(.gray500)
        }
    }
}

struct EmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StonesLogo(size: 96)
            Tagline(size: 28).padding(.top, 12)
            Text("Bis hierher hat uns der HERR geholfen.")
                .font(TS.headlineS)
                .foregroundColor(.green800)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            Text("1. Samuel 7,12")
                .font(TS.labelM)
                .foregroundColor(.gold800)
                .padding(.top, 6)
            Text("Halte fest, was Gott in deinem Leben getan hat – damit du es nie vergisst und andere davon erzählen kannst.")
                .font(TS.bodyL)
                .foregroundColor(.gray700)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            Button("Erstes Zeugnis festhalten", action: onAdd)
                .buttonStyle(PillButtonStyle())
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 16)
    }
}
