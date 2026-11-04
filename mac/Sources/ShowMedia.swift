// ddir macOS backend — real media for the stage, fetched from the internet once and cached.
//
//   ddir stage fetch [--force]     download + prepare media/ (needs network the first time)
//
// Sources (both allow commercial use, credit kept in media/sources.json):
//   * NASA / STScI public-domain imagery (JWST Carina Nebula, Hubble spiral galaxy)
//   * "Another space background track" by yd — CC0, OpenGameArt
//
// Preparation: a 12 s portrait Ken Burns clip (540x960, H.264) per image, so the triptych
// columns are full-bleed instead of letterboxed. If the network is unavailable, `stage` falls
// back to the generated assets (ShowAssets) — the show never breaks.

import AVFoundation
import AppKit
import Foundation

enum ShowMedia {
    static func dir() -> URL { ShowAssets.dir().appendingPathComponent("media", isDirectory: true) }
    static func url(_ name: String) -> URL { dir().appendingPathComponent(name) }

    struct Source: Codable {
        var file: String
        var kind: String           // "video" | "audio" | "still"
        var title: String
        var source: String
        var url: String
        var license: String
    }

    static let sources: [Source] = [
        Source(file: "carina.jpg", kind: "still",
               title: "Carina Nebula (JWST NIRCam, Cosmic Cliffs)",
               source: "NASA / STScI — image carina_nebula",
               url: "https://images-assets.nasa.gov/image/carina_nebula/carina_nebula~large.jpg",
               license: "Public Domain (NASA)"),
        Source(file: "galaxy.jpg", kind: "still",
               title: "Hubble spiral galaxy",
               source: "NASA / ESA — GSFC_20171208_Archive_e000158",
               url: "https://images-assets.nasa.gov/image/GSFC_20171208_Archive_e000158/GSFC_20171208_Archive_e000158~large.jpg",
               license: "Public Domain (NASA)"),
        Source(file: "score.mp3", kind: "audio",
               title: "Another space background track",
               source: "yd — OpenGameArt",
               url: "https://opengameart.org/sites/default/files/audio_preview/ObservingTheStar.ogg.mp3",
               license: "CC0 1.0"),
    ]

    static func source(_ file: String) -> Source? { sources.first { $0.file == file } }

    // MARK: - what `stage` should play

    /// Portrait clips prepared from the downloaded stills (empty -> caller falls back to generated).
    static func clips() -> [URL] {
        let a = url("nebula.mp4"), b = url("galaxy.mp4")
        var out: [URL] = []
        if FileManager.default.fileExists(atPath: a.path) { out.append(a) }
        if FileManager.default.fileExists(atPath: b.path) { out.append(b) }
        return out
    }

    /// Music: the CC0 mp3 if downloaded, else the generated pad.
    static func score() -> URL? {
        let mp3 = url("score.mp3")
        if FileManager.default.fileExists(atPath: mp3.path) { return mp3 }
        let wav = ShowAssets.url("score.wav")
        if FileManager.default.fileExists(atPath: wav.path) { return wav }
        return nil
    }

    static func hasMedia() -> Bool { !clips().isEmpty }

    // MARK: - fetch

    /// Download the sources once, then prepare the two portrait clips. Returns the manifest rows.
    static func fetch(force: Bool = false) throws -> [Source] {
        try FileManager.default.createDirectory(at: dir(), withIntermediateDirectories: true)
        for s in sources {
            let dest = url(s.file)
            if force || !FileManager.default.fileExists(atPath: dest.path) {
                let tmp = dest.appendingPathExtension("part")
                try? FileManager.default.removeItem(at: tmp)
                try download(s.url, to: tmp)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
        }
        let stills = [("carina.jpg", "nebula.mp4", (1.00, 1.14), (CGPoint(x: 0.48, y: 0.60), CGPoint(x: 0.52, y: 0.50))),
                      ("galaxy.jpg", "galaxy.mp4", (1.02, 1.18), (CGPoint(x: 0.50, y: 0.55), CGPoint(x: 0.46, y: 0.46)))]
        for (still, clip, zoom, pan) in stills {
            let out = url(clip)
            if force || !FileManager.default.fileExists(atPath: out.path) {
                try kenBurns(image: url(still), to: out, seconds: 12,
                             size: (540, 960), zoom: zoom, pan: pan)
            }
        }
        let manifest = try JSONEncoder().encode(sources)
        try manifest.write(to: dir().appendingPathComponent("sources.json"))
        Store.shared.log("stage: media fetched (\(sources.map { $0.file }.joined(separator: ", ")))")
        return sources
    }

    private static func download(_ urlString: String, to dest: URL) throws {
        guard let u = URL(string: urlString) else { throw NSError(domain: "ddir", code: 1) }
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        var request = URLRequest(url: u, timeoutInterval: 240)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ddir-stage/1.0", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: request) { tmp, resp, err in
            defer { sem.signal() }
            if let err { failure = err; return }
            guard let tmp, let code = (resp as? HTTPURLResponse)?.statusCode, code == 200 else {
                failure = NSError(domain: "ddir", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"])
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
            } catch { failure = error }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 280)
        if let failure { throw failure }
        if !FileManager.default.fileExists(atPath: dest.path) {
            throw NSError(domain: "ddir", code: 3, userInfo: [NSLocalizedDescriptionKey: "download timed out"])
        }
    }

    // MARK: - Ken Burns clip from a still

    static func kenBurns(image: URL, to output: URL, seconds: Double, size: (Int, Int),
                         zoom: (Double, Double), pan: (CGPoint, CGPoint)) throws {
        guard let src = CGImageSourceCreateWithURL(image as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "ddir", code: 4, userInfo: [NSLocalizedDescriptionKey: "cannot read \(image.lastPathComponent)"])
        }
        let W = Double(cg.width), H = Double(cg.height)
        let (outW, outH) = size
        let fps = 30
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW, AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: outW,
            kCVPixelBufferHeightKey as String: outH,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "ddir", code: 5) }
        writer.startSession(atSourceTime: .zero)

        let total = Int(seconds * Double(fps))
        let aspect = Double(outW) / Double(outH)
        for frame in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1500) }
            let t = Double(frame) / Double(max(total - 1, 1))
            let z = zoom.0 + (zoom.1 - zoom.0) * t
            var cropH = H / z
            var cropW = cropH * aspect
            if cropW > W { cropW = W; cropH = cropW / aspect }
            let cx = (pan.0.x + (pan.1.x - pan.0.x) * t) * W
            let cy = (pan.0.y + (pan.1.y - pan.0.y) * t) * H
            var cropX = cx - cropW / 2
            var cropY = cy - cropH / 2
            cropX = min(max(0, cropX), W - cropW)
            cropY = min(max(0, cropY), H - cropH)
            let s = Double(outH) / cropH

            guard let pool = adaptor.pixelBufferPool else { break }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pb = pbOut else { break }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: outW, height: outH,
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.interpolationQuality = .high
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
                let rect = CGRect(x: -cropX * s, y: -(H - cropY - cropH) * s,
                                  width: W * s, height: H * s)
                ctx.draw(cg, in: rect)
                // soft vignette: transparent centre -> dark edges (a hard-edged disc looks like a bug)
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                                                  CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)] as CFArray,
                                         locations: [0, 1]) {
                    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: Double(outW) / 2, y: Double(outH) / 2),
                                           startRadius: Double(outH) * 0.30,
                                           endCenter: CGPoint(x: Double(outW) / 2, y: Double(outH) / 2),
                                           endRadius: Double(outH) * 0.72, options: [])
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        _ = sem.wait(timeout: .now() + 60)
    }

    // MARK: - looping score

    /// afplay doesn't loop: a tiny wrapper restarts it, and killing the wrapper stops the child.
    static func scoreLoopScript() -> URL {
        let u = url("loop-score.sh")
        let body = """
        #!/bin/bash
        trap 'kill $AF 2>/dev/null; exit 0' TERM INT
        while :; do
          /usr/bin/afplay -v "${2:-0.30}" "$1" &
          AF=$!
          wait $AF
        done
        """
        try? body.write(to: u, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return u
    }
}
