//
//  MediaViews.swift
//  Eben-Ezer
//
//  Vorschaubilder, Bild-/Videobetrachter, Audio-Player, Sprachaufnahme und Kamera.
//

import SwiftUI
import AVKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Vorschaubilder

enum Thumbs {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ url: URL, type: MediaType, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
            switch type {
            case .image:
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            case .video:
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
                for seconds in [0.5, 0.0] {
                    if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                        return UIImage(cgImage: result.image)
                    }
                }
                return nil
            case .audio:
                return nil
            }
        }.value
        if let image = image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// Quadratisches Vorschaubild für Foto oder Video.
struct MediaThumb: View {
    let url: URL
    let type: MediaType
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gold100
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            }
            if type == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: size / 2.6))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: url) {
            image = await Thumbs.load(url, type: type, maxPixel: size * 3)
        }
    }
}

// MARK: - Betrachter (Vollbild)

struct MediaViewerItem: Identifiable {
    let id = UUID()
    let url: URL
    let type: MediaType
}

struct MediaViewer: View {
    let item: MediaViewerItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if item.type == .video {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear {
                        if player == nil {
                            try? AVAudioSession.sharedInstance().setCategory(.playback)
                            let p = AVPlayer(url: item.url)
                            player = p
                            p.play()
                        }
                    }
                    .onDisappear { player?.pause() }
            } else {
                ZoomableImage(url: item.url)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.22)))
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Schließen")
        }
    }
}

/// Bild mit Zoomen (zwei Finger) und Doppeltippen.
struct ZoomableImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = min(max(lastScale * v, 1), 5) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 { reset() }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        if scale > 1 {
                            reset()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { scale = 2.5 }
                            lastScale = 2.5
                        }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { image = await Thumbs.load(url, type: .image, maxPixel: 3000) }
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1
            offset = .zero
        }
        lastScale = 1
        lastOffset = .zero
    }
}

// MARK: - Audio abspielen

final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private let url: URL
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(url: URL) {
        self.url = url
        super.init()
        duration = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    private func ensurePlayer() -> AVAudioPlayer? {
        if let p = player { return p }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.delegate = self
        p.prepareToPlay()
        player = p
        duration = p.duration
        return p
    }

    func toggle() {
        guard let p = ensurePlayer() else { return }
        if p.isPlaying {
            p.pause()
            playing = false
            stopTimer()
        } else {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback)
            try? session.setActive(true)
            p.play()
            playing = true
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let p = ensurePlayer() else { return }
        p.currentTime = fraction * p.duration
        position = p.currentTime
    }

    func stop() {
        player?.stop()
        playing = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.position = self?.player?.currentTime ?? 0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.playing = false
            self.position = 0
            self.stopTimer()
        }
    }
}

func formatSeconds(_ t: TimeInterval) -> String {
    let s = t.isFinite ? max(0, Int(t)) : 0
    return String(format: "%d:%02d", s / 60, s % 60)
}

struct AudioPlayerView<Trailing: View>: View {
    @StateObject private var playback: AudioPlayback
    let label: String
    let trailing: Trailing

    init(url: URL, label: String, @ViewBuilder trailing: () -> Trailing) {
        _playback = StateObject(wrappedValue: AudioPlayback(url: url))
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.offWhite)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.green800))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.playing ? "Pause" : "Abspielen")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                        .foregroundColor(.gold800)
                    Text(label.isBlank ? "Audio" : label)
                        .font(TS.bodyM)
                        .foregroundColor(.green800)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(formatSeconds(playback.position)) / \(formatSeconds(playback.duration))")
                        .font(TS.labelS)
                        .foregroundColor(.gray700)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { playback.duration > 0 ? min(1, playback.position / playback.duration) : 0 },
                    set: { playback.seek(to: $0) }
                ))
                .tint(.green800)
            }
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.gold100))
        .onDisappear { playback.stop() }
    }
}

extension AudioPlayerView where Trailing == EmptyView {
    init(url: URL, label: String) {
        self.init(url: url, label: label) { EmptyView() }
    }
}

// MARK: - Sprachaufnahme

final class Recorder: NSObject, ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var seconds = 0
    private(set) var url: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        guard r.record() else { throw CocoaError(.fileWriteUnknown) }
        recorder = r
        self.url = url
        seconds = 0
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.seconds += 1
        }
    }

    /// Beendet die Aufnahme. Gibt `true` zurück, wenn eine gültige Datei entstanden ist.
    @discardableResult
    func stop() -> Bool {
        timer?.invalidate()
        timer = nil
        guard let r = recorder else { return false }
        r.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = url else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    func discard() {
        if recording { stop() }
        if let url = url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }
}

struct RecorderSheet: View {
    let media: MediaFiles
    let onDone: (Attachment?) -> Void
    @StateObject private var recorder = Recorder()
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Sprachaufnahme")
                .font(TS.headlineS)
                .foregroundColor(.green800)
            Image(systemName: "record.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(.red800)
                .opacity(recorder.recording ? 1 : 0)
            Text(verbatim: String(format: "%d:%02d", recorder.seconds / 60, recorder.seconds % 60))
                .font(.system(size: 48, weight: .heavy))
                .foregroundColor(.green800)
                .monospacedDigit()
            Text(recorder.recording ? "Aufnahme läuft …" : "Erzähle, was Gott getan hat.")
                .font(TS.bodyM)
                .foregroundColor(.gray700)
            if let errorText = errorText {
                Text(errorText)
                    .font(TS.bodyM)
                    .foregroundColor(.red800)
                    .multilineTextAlignment(.center)
            }
            if recorder.recording {
                Button("Stopp & übernehmen") { finish() }
                    .buttonStyle(PillButtonStyle(fill: .green800, text: .offWhite))
            } else {
                Button("Aufnahme starten") { start() }
                    .buttonStyle(PillButtonStyle())
            }
            Button("Abbrechen") { cancel() }
                .font(TS.labelL)
                .foregroundColor(.green800)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .interactiveDismissDisabled(recorder.recording)
        .onDisappear { if recorder.recording { recorder.discard() } }
    }

    private func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    errorText = "Ohne Mikrofon-Zugriff ist keine Aufnahme möglich. Du kannst ihn in der Einstellungen-App unter „Eben-Ezer“ erlauben."
                    return
                }
                do {
                    try recorder.start(to: media.newURL(ext: "m4a"))
                    errorText = nil
                } catch {
                    errorText = "Aufnahme konnte nicht gestartet werden."
                }
            }
        }
    }

    private func finish() {
        let ok = recorder.stop()
        guard ok, let url = recorder.url else {
            recorder.discard()
            onDone(nil)
            return
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        onDone(Attachment(type: .audio, fileName: url.lastPathComponent, label: "Sprachaufnahme " + f.string(from: Date())))
    }

    private func cancel() {
        recorder.discard()
        onDone(nil)
    }
}

// MARK: - Kamera

struct CameraPicker: UIViewControllerRepresentable {
    enum Mode: String, Identifiable {
        case photo, video
        var id: String { rawValue }
    }

    let mode: Mode
    let onFinish: (UIImage?, URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [mode == .photo ? UTType.image.identifier : UTType.movie.identifier]
        if mode == .video {
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?, URL?) -> Void

        init(onFinish: @escaping (UIImage?, URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage, info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil, nil)
        }
    }
}
