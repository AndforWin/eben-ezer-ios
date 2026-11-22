//
//  Zip.swift
//  Eben-Ezer
//
//  Minimaler ZIP-Schreiber/-Leser für die Sicherung.
//  Liest auch die (komprimierten) Sicherungen der Android-App.
//

import Foundation
import Compression

// MARK: - Hilfen

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var v: T = 0
        for i in 0..<MemoryLayout<T>.size {
            v |= T(self[startIndex + offset + i]) << (8 * i)
        }
        return v
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { t in
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                for b in buf { c = t[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
            }
        }
        return c ^ 0xFFFF_FFFF
    }
}

enum ZipError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "Die Sicherung ist zu groß (über 4 GB)." }
}

// MARK: - Schreiben (unkomprimiert)

final class ZipWriter {
    private let handle: FileHandle
    private var central = Data()
    private var count: UInt16 = 0
    private var offset: UInt64 = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        dosDate = UInt16((((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
    }

    func add(name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        guard data.count < Int(UInt32.max), offset + UInt64(30 + nameData.count + data.count) < UInt64(UInt32.max) else {
            throw ZipError.tooLarge
        }
        let size = UInt32(data.count)

        var local = Data()
        local.appendLE(UInt32(0x0403_4b50))
        local.appendLE(UInt16(20))      // Version
        local.appendLE(UInt16(0x0800))  // UTF-8-Dateinamen
        local.appendLE(UInt16(0))       // gespeichert (keine Kompression)
        local.appendLE(dosTime)
        local.appendLE(dosDate)
        local.appendLE(crc)
        local.appendLE(size)
        local.appendLE(size)
        local.appendLE(UInt16(nameData.count))
        local.appendLE(UInt16(0))
        local.append(nameData)
        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)

        var c = Data()
        c.appendLE(UInt32(0x0201_4b50))
        c.appendLE(UInt16(20))
        c.appendLE(UInt16(20))
        c.appendLE(UInt16(0x0800))
        c.appendLE(UInt16(0))
        c.appendLE(dosTime)
        c.appendLE(dosDate)
        c.appendLE(crc)
        c.appendLE(size)
        c.appendLE(size)
        c.appendLE(UInt16(nameData.count))
        c.appendLE(UInt16(0))  // Extra
        c.appendLE(UInt16(0))  // Kommentar
        c.appendLE(UInt16(0))  // Disk
        c.appendLE(UInt16(0))  // interne Attribute
        c.appendLE(UInt32(0))  // externe Attribute
        c.appendLE(UInt32(offset))
        c.append(nameData)
        central.append(c)

        offset += UInt64(local.count + data.count)
        count += 1
    }

    func finish() throws {
        var end = Data()
        end.appendLE(UInt32(0x0605_4b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(count)
        end.appendLE(count)
        end.appendLE(UInt32(central.count))
        end.appendLE(UInt32(offset))
        end.appendLE(UInt16(0))
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.close()
    }
}

// MARK: - Lesen (unkomprimiert und Deflate)

struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let size: Int
    let localOffset: Int
    var isDirectory: Bool { name.hasSuffix("/") }
}

final class ZipReader {
    private let bytes: Data
    private(set) var entries: [ZipEntry] = []

    init(url: URL) throws {
        bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count >= 22 else { throw BackupError.invalid }

        // Ende des zentralen Verzeichnisses suchen
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if bytes.readLE(UInt32.self, at: i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw BackupError.invalid }

        let total = Int(bytes.readLE(UInt16.self, at: eocd + 10))
        var p = Int(bytes.readLE(UInt32.self, at: eocd + 16))
        for _ in 0..<total {
            guard p + 46 <= bytes.count, bytes.readLE(UInt32.self, at: p) == 0x0201_4b50 else { throw BackupError.invalid }
            let method = bytes.readLE(UInt16.self, at: p + 10)
            let csize = Int(bytes.readLE(UInt32.self, at: p + 20))
            let usize = Int(bytes.readLE(UInt32.self, at: p + 24))
            let n = Int(bytes.readLE(UInt16.self, at: p + 28))
            let m = Int(bytes.readLE(UInt16.self, at: p + 30))
            let k = Int(bytes.readLE(UInt16.self, at: p + 32))
            let off = Int(bytes.readLE(UInt32.self, at: p + 42))
            guard p + 46 + n <= bytes.count else { throw BackupError.invalid }
            let name = String(decoding: bytes.subdata(in: (p + 46)..<(p + 46 + n)), as: UTF8.self)
            entries.append(ZipEntry(name: name, method: method, compressedSize: csize, size: usize, localOffset: off))
            p += 46 + n + m + k
        }
    }

    func extract(_ e: ZipEntry) throws -> Data {
        let o = e.localOffset
        guard o + 30 <= bytes.count, bytes.readLE(UInt32.self, at: o) == 0x0403_4b50 else { throw BackupError.invalid }
        let n = Int(bytes.readLE(UInt16.self, at: o + 26))
        let m = Int(bytes.readLE(UInt16.self, at: o + 28))
        let start = o + 30 + n + m
        guard start + e.compressedSize <= bytes.count else { throw BackupError.invalid }
        let raw = bytes.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return try inflate(raw, size: e.size)
        default: throw BackupError.invalid
        }
    }

    /// Entpackt rohe DEFLATE-Daten (RFC 1951), wie sie in ZIP-Dateien stehen.
    private func inflate(_ src: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (s: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let sp = s.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, size, sp, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw BackupError.invalid }
        return out
    }
}
