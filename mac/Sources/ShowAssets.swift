// ddir macOS backend — demo assets for `ddir show`.
// Everything is generated on this machine (no ffmpeg, no downloads):
//   index.html   animated sci-fi dashboard (Safari window, long page so scrolling is visible)
//   code.swift   a real-looking Swift file that the show types into VS Code
//   clip1.mov    H.264 "NEURAL LINK" clip (AVAssetWriter)
//   clip2.mov    H.264 "SIGNAL 02" clip
//   score.wav    ambient pad, played in the background during the show

import AVFoundation
import AppKit
import CoreGraphics
import CoreText

enum ShowAssets {
    static func dir() -> URL {
        Store.shared.home().appendingPathComponent("show", isDirectory: true)
    }

    static func url(_ name: String) -> URL { dir().appendingPathComponent(name) }

    struct Inventory {
        var name: String
        var path: String
        var bytes: Int
    }

    /// Bump when the generated content changes; `ensure()` then rebuilds every asset once.
    static let assetVersion = "2"
    private static func versionPath() -> URL { dir().appendingPathComponent(".version") }

    static func ensure(force: Bool = false) throws -> [Inventory] {
        try FileManager.default.createDirectory(at: dir(), withIntermediateDirectories: true)
        var rebuild = force
        if (try? String(contentsOf: versionPath(), encoding: .utf8)) != assetVersion { rebuild = true }
        let files: [(String, () throws -> Void)] = [
            ("index.html", { try write(html(), "index.html") }),
            ("code.swift", { try write(code(), "code.swift") }),
            ("editor.html", { try write(editorHTML(), "editor.html") }),
            ("score.wav", { try makeScore(url("score.wav")) }),
            ("clip1.mov", { try makeVideo(url("clip1.mov"), seconds: 8, width: 540, height: 960,
                                          top: NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.95, alpha: 1),
                                          bottom: NSColor(calibratedRed: 0.45, green: 0.05, blue: 0.55, alpha: 1),
                                          title: "NEURAL LINK", subtitle: "AGENT 01 · DESKTOP DIRECTOR") }),
            ("clip2.mov", { try makeVideo(url("clip2.mov"), seconds: 8, width: 540, height: 960,
                                          top: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.1, alpha: 1),
                                          bottom: NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.35, alpha: 1),
                                          title: "SIGNAL 02", subtitle: "AGENT 02 · WINDOW ORCHESTRATION") }),
        ]
        var out: [Inventory] = []
        for (name, make) in files {
            let u = url(name)
            let exists = FileManager.default.fileExists(atPath: u.path)
            if rebuild || !exists {
                try make()
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
            out.append(Inventory(name: name, path: u.path, bytes: (attrs?[.size] as? Int) ?? 0))
        }
        try? assetVersion.write(to: versionPath(), atomically: true, encoding: .utf8)
        return out
    }

    private static func write(_ body: String, _ name: String) throws {
        try body.write(to: url(name), atomically: true, encoding: .utf8)
    }

    // MARK: - dashboard page

    static func html() -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>DDIR · Mission Control</title>
        <style>
        :root{--cyan:#39f6ff;--amber:#ffcb45;--bg:#04070d}
        *{box-sizing:border-box}
        html,body{margin:0;background:var(--bg);color:#cfe9ff;font-family:-apple-system,"SF Mono",Menlo,monospace}
        #wrap{height:100vh;display:flex;flex-direction:column}
        header{display:flex;align-items:center;gap:18px;padding:18px 26px;border-bottom:1px solid #16324a}
        .dot{width:10px;height:10px;border-radius:50%;background:var(--cyan);box-shadow:0 0 12px var(--cyan)}
        h1{margin:0;font-size:22px;letter-spacing:6px;font-weight:600;color:#eaf7ff}
        .sub{color:#5f89a8;font-size:12px;letter-spacing:3px}
        .spacer{flex:1}
        .chip{border:1px solid #1d4b64;color:var(--cyan);padding:4px 10px;border-radius:999px;font-size:11px;letter-spacing:2px}
        main{flex:1;display:grid;grid-template-columns:1.1fr .9fr;gap:18px;padding:18px 26px;min-height:0}
        .panel{border:1px solid #14314a;border-radius:14px;position:relative;overflow:hidden;background:radial-gradient(120% 90% at 30% 0%,#0a2334 0%,#04070d 70%)}
        .panel h2{margin:0;padding:12px 16px;font-size:11px;letter-spacing:3px;color:#6ea8c9;border-bottom:1px solid #10283c}
        canvas{width:100%;height:calc(100% - 42px);display:block}
        #log{overflow:auto;height:calc(100% - 42px);padding:12px 16px;font-size:12px;line-height:1.9;color:#8fc3dd}
        #log b{color:var(--amber);font-weight:500}
        .row{display:flex;justify-content:space-between;border-bottom:1px dashed #0f2536;padding:2px 0}
        .k{color:#4f7d99}
        .v{color:#d8f4ff}
        footer{padding:12px 26px;border-top:1px solid #16324a;display:flex;gap:26px;font-size:11px;color:#4f7d99;letter-spacing:2px}
        .bar{height:4px;background:#0c2233;border-radius:3px;overflow:hidden;margin-top:8px}
        .bar i{display:block;height:100%;background:linear-gradient(90deg,var(--cyan),#a05bff);width:62%}
        .scan{position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(57,246,255,.05) 0 1px,transparent 1px 4px);pointer-events:none;mix-blend-mode:screen}
        </style></head>
        <body><div id="wrap" style="height:100vh;overflow:hidden">
        <header>
          <div class="dot"></div><h1>DESKTOP DIRECTOR</h1>
          <div class="sub">MULTI-AGENT WINDOW ORCHESTRATION</div>
          <div class="spacer"></div><div class="chip" id="clock">--:--:--</div>
        </header>
        <main>
          <section class="panel"><h2>WINDOW ARBITER · LIVE</h2><canvas id="radar"></canvas><div class="scan"></div></section>
          <section class="panel"><h2>TELEMETRY</h2>
            <div id="log">
              <div class="row"><span class="k">agent</span><span class="v">dsh-mac</span></div>
              <div class="row"><span class="k">mode</span><span class="v">semi</span></div>
              <div class="row"><span class="k">leases</span><span class="v" id="leases">2 / 3</span></div>
              <div class="row"><span class="k">focus</span><span class="v">none</span></div>
              <div class="row"><span class="k">idle</span><span class="v" id="idle">0s</span></div>
              <div class="bar"><i></i></div>
              <p style="margin:14px 0 6px;color:#4f7d99;letter-spacing:2px;font-size:10px">MISSION LOG</p>
              <div id="feed"></div>
            </div>
          </section>
        </main>
        <footer><span>T+ <b id="t">00:00</b></span><span>WINDOWS 3</span><span>DISPLAY cg-1</span><span>BUILD 0.10.0</span><span>UPLINK STABLE</span></footer>
        </div>
        <script>
        const c=document.getElementById('radar'),x=c.getContext('2d');let t=0;
        function fit(){c.width=c.clientWidth*devicePixelRatio;c.height=c.clientHeight*devicePixelRatio;}
        addEventListener('resize',fit);fit();
        const blips=Array.from({length:9},()=>({a:Math.random()*6.28,r:.25+Math.random()*.65,s:.4+Math.random()*1.2}));
        function draw(){t+=0.016;const w=c.width,h=c.height,cx=w/2,cy=h/2,R=Math.min(w,h)*.42;
          x.clearRect(0,0,w,h);
          x.strokeStyle='rgba(57,246,255,.18)';x.lineWidth=1*devicePixelRatio;
          for(let i=1;i<=4;i++){x.beginPath();x.arc(cx,cy,R*i/4,0,6.283);x.stroke();}
          for(let i=0;i<12;i++){const a=i*Math.PI/6;x.beginPath();x.moveTo(cx,cy);x.lineTo(cx+Math.cos(a)*R,cy+Math.sin(a)*R);x.stroke();}
          const a=t*.9;const g=x.createConicGradient?null:null;
          x.save();x.translate(cx,cy);
          x.rotate(a);const sweep=x.createLinearGradient(0,0,R,0);sweep.addColorStop(0,'rgba(57,246,255,.55)');sweep.addColorStop(1,'rgba(57,246,255,0)');
          x.fillStyle=sweep;x.beginPath();x.moveTo(0,0);x.arc(0,0,R,-.45,0);x.closePath();x.fill();x.restore();
          for(const b of blips){const ang=b.a+t*b.s*.3,px=cx+Math.cos(ang)*R*b.r,py=cy+Math.sin(ang)*R*b.r;
            x.fillStyle='rgba(255,203,69,.9)';x.beginPath();x.arc(px,py,2.4*devicePixelRatio,0,6.283);x.fill();
            x.strokeStyle='rgba(255,203,69,.25)';x.beginPath();x.arc(px,py,7*devicePixelRatio,0,6.283);x.stroke();}
          requestAnimationFrame(draw);}
        draw();
        const feed=document.getElementById('feed');const lines=[
          'claim · 3 windows · side-by-side','lease ls_6aea · ttl 300s','typing session attached to editor',
          'scroll event dispatched to dashboard','media agent 01 online','media agent 02 online',
          'focus token free','release · layout restored','heartbeat · ttl refreshed','plan · 2 columns · gap 16','window 75098:7449 · 538x942','window 75098:7451 · 538x942','window 75098:7453 · 538x942','hud · thumbnails online','media · signal 01 playing','media · signal 02 playing','typing · 1284 chars','scroll · mission log','lease expiry watch · ok','agent 02 joined the stage','focus token · free','audit · claim/preempt/release','archive · layout snapshot saved','night mode · engaged'];
        let n=0;setInterval(()=>{const d=document.createElement('div');d.className='row';
          d.innerHTML='<span class="k">'+(new Date()).toTimeString().slice(0,8)+'</span><span class="v">'+lines[n%lines.length]+'</span>';
          feed.appendChild(d);if(feed.children.length>24)feed.removeChild(feed.firstChild);n++;},900);
        setInterval(()=>{document.getElementById('clock').textContent=(new Date()).toTimeString().slice(0,8);
          document.getElementById('t').textContent=String(Math.floor(t)).padStart(2,'0')+':'+String(Math.floor(t*10)%60).padStart(2,'0');},250);
        // hash params: #scroll=SECONDS scrolls the mission log (demo beat: "agent scrolls the view")
        const params=new URLSearchParams(location.hash.slice(1));
        const scrollAt=parseFloat(params.get('scroll')||'0');
        if(scrollAt>0){setTimeout(()=>{const box=document.getElementById('log');let y=0;
          const timer=setInterval(()=>{y+=3;box.scrollTop=y;if(y>box.scrollHeight)clearInterval(timer);},40);},scrollAt*1000);}
        </script></body></html>
        """
    }

    // MARK: - code that gets typed

    static func code() -> String {
        """
        // AgentOrchestrator.swift — generated for the ddir stage demo
        import Foundation

        struct WindowLease {
            let id: String
            let window: String
            let ttl: TimeInterval
            let priority: Priority
        }

        enum Priority: Int, Comparable {
            case low = 0, normal = 1, high = 2, user = 3
            static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        final class Director {
            private var leases: [String: WindowLease] = [:]
            private let lock = NSLock()
            private(set) var mode: Mode = .off

            enum Mode: String { case off, semi, auto }

            func claim(_ windows: [String], priority: Priority) -> [WindowLease] {
                lock.lock(); defer { lock.unlock() }
                let cells = layout(count: windows.count)
                var granted: [WindowLease] = []
                for (i, w) in windows.enumerated() where leases.count < 3 {
                    guard leases[w] == nil else { continue }   // I1: one writer per window
                    let lease = WindowLease(id: "ls_\\(i)", window: w,
                                            ttl: 300, priority: priority)
                    leases[w] = lease
                    granted.append(lease)
                    place(w, at: cells[i])
                }
                return granted
            }

            private func layout(count n: Int) -> [(Int, Int, Int, Int)] {
                let (gap, width, height) = (16, 1680, 1050)
                let col = (width - (n + 1) * gap) / max(n, 1)
                return (0..<max(n, 1)).map { i in
                    (gap + i * (col + gap), gap, col, height - 2 * gap)
                }
            }

            private func place(_ window: String, at rect: (Int, Int, Int, Int)) {
                // Accessibility API: position + size, points, never pixels
                ax_set(window, rect)
            }

            func releaseAll() {
                lock.lock(); defer { lock.unlock() }
                for (w, _) in leases { ax_restore(w) }
                leases.removeAll()
            }
        }
        """
    }


    // MARK: - the "IDE" page: types the code character by character

    static func editorHTML() -> String {
        let codeJSON = (try? JSONEncoder().encode(code())).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>code.swift — ddir stage</title>
        <style>
        :root{--bg:#0b0f17;--panel:#0e141f;--line:#1b2230;--txt:#d7e6ff;--dim:#5b6b85;--cyan:#39f6ff;--amber:#ffcb45;--green:#7ee787;--purple:#c7a0ff}
        *{box-sizing:border-box}
        html,body{margin:0;height:100%;background:var(--bg);color:var(--txt);font:13px/1.55 "SF Mono",Menlo,monospace;overflow:hidden}
        #app{height:100%;display:flex;flex-direction:column}
        .titlebar{display:flex;align-items:center;gap:10px;padding:10px 14px;background:var(--panel);border-bottom:1px solid var(--line)}
        .lights i{display:inline-block;width:11px;height:11px;border-radius:50%;margin-right:6px}
        .lights i:nth-child(1){background:#ff5f57}.lights i:nth-child(2){background:#febc2e}.lights i:nth-child(3){background:#28c840}
        .file{color:#8fb2d9;font-size:12px;letter-spacing:.5px}
        .agent{margin-left:auto;color:var(--cyan);font-size:11px;letter-spacing:2px}
        .agent b{color:var(--amber)}
        #code{flex:1;overflow:hidden;padding:14px 0 40px;position:relative}
        .ln{display:flex;gap:14px;padding:0 16px;white-space:pre}
        .ln .n{width:34px;text-align:right;color:#35455c;user-select:none;flex:none}
        .ln .c{white-space:pre-wrap;word-break:break-word}
        .caret{display:inline-block;width:8px;background:var(--cyan);animation:blink 1s steps(1) infinite;color:transparent;vertical-align:text-bottom}
        @keyframes blink{50%{opacity:0}}
        .kw{color:var(--purple)}.str{color:var(--green)}.cmt{color:#4f627a;font-style:italic}
        .typ{color:var(--amber)}.num{color:#ff9f6e}
        .statusbar{display:flex;gap:18px;padding:7px 14px;background:#0a3f52;color:#c8f4ff;font-size:11px;letter-spacing:1px}
        .statusbar .right{margin-left:auto;display:flex;gap:16px}
        .pulse{width:7px;height:7px;border-radius:50%;background:var(--green);box-shadow:0 0 10px var(--green);align-self:center}
        </style></head>
        <body><div id="app">
          <div class="titlebar"><span class="lights"><i></i><i></i><i></i></span>
            <span class="file">code.swift — ~/.ddir/show</span>
            <span class="agent">AGENT <b>WRITING</b></span>
          </div>
          <div id="code"></div>
          <div class="statusbar"><span>◆ ddir stage</span><span id="pos">Ln 1, Col 1</span><span>UTF-8</span><span>Swift</span>
            <span class="right"><span id="chars">0 chars</span><span class="pulse"></span><span>leased · 3</span></span>
          </div>
        </div>
        <script>
        const CODE = \(codeJSON);
        const NL = String.fromCharCode(10);
        const params = new URLSearchParams(location.hash.slice(1));
        const startDelay = parseFloat(params.get('type') || '1.2') * 1000;
        const speed = parseFloat(params.get('speed') || '9');
        const codeEl = document.getElementById('code');
        const posEl = document.getElementById('pos');
        const charsEl = document.getElementById('chars');
        const KEYWORDS = ['import','struct','final','class','enum','let','var','func','private','set','return','static','if','else','for','in','where','guard','self','init'];
        const TYPES = ['Int','String','Bool','Double','TimeInterval','Priority','Mode','WindowLease','Director','NSLock','Foundation','Comparable'];
        function esc(c){ return c === '<' ? '&lt;' : c === '>' ? '&gt;' : c === '&' ? '&amp;' : c; }
        function highlight(src) {
          let out = '';
          for (let i = 0; i < src.length;) {
            const c = src[i];
            if (c === '"' || c === "'") {
              let j = i + 1;
              while (j < src.length && src[j] !== c) j++;
              out += '<span class="str">' + esc(src.slice(i, j + 1)) + '</span>';
              i = j + 1; continue;
            }
            if (c === '/' && src[i + 1] === '/') { out += '<span class="cmt">' + esc(src.slice(i)) + '</span>'; break; }
            if (/[A-Za-z_]/.test(c)) {
              let j = i;
              while (j < src.length && /[A-Za-z0-9_]/.test(src[j])) j++;
              const w = src.slice(i, j);
              out += KEYWORDS.indexOf(w) >= 0 ? '<span class="kw">' + w + '</span>'
                   : TYPES.indexOf(w) >= 0 ? '<span class="typ">' + w + '</span>' : w;
              i = j; continue;
            }
            if (/[0-9]/.test(c)) {
              let j = i;
              while (j < src.length && /[0-9.]/.test(src[j])) j++;
              out += '<span class="num">' + src.slice(i, j) + '</span>';
              i = j; continue;
            }
            out += esc(c); i++;
          }
          return out;
        }
        let typed = '';
        function render() {
          const parts = typed.split(NL);
          codeEl.innerHTML = parts.map((line, idx) => {
            const last = idx === parts.length - 1;
            return '<div class="ln"><span class="n">' + (idx + 1) + '</span><span class="c">' +
                   highlight(line) + (last ? '<span class="caret">|</span>' : '') + '</span></div>';
          }).join('');
          posEl.textContent = 'Ln ' + parts.length + ', Col ' + (parts[parts.length - 1].length + 1);
          charsEl.textContent = typed.length + ' chars';
        }
        let i = 0;
        function step() {
          if (i >= CODE.length) {
            document.querySelector('.agent').innerHTML = 'AGENT <b>IDLE</b>';
            return;
          }
          const ch = CODE[i++];
          typed += ch;
          render();
          setTimeout(step, speed + (ch === NL ? 55 : 0));
        }
        render();
        setTimeout(step, startDelay);
        </script></body></html>
        """

    }
    // MARK: - audio

    static func makeScore(_ url: URL) throws {
        let seconds = 24.0
        let rate = 44100.0
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let left = buf.floatChannelData![0]
        let right = buf.floatChannelData![1]
        // slow minor pad: A2/C3/E3 moving to F2/A2/C3
        let chords: [[Double]] = [
            [110.0, 130.81, 164.81], [87.31, 110.0, 130.81],
            [98.0, 116.54, 146.83], [110.0, 130.81, 164.81],
        ]
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let beat = min(Int(t / 6.0), chords.count - 1)
            var l = 0.0, r = 0.0
            for (k, f) in chords[beat].enumerated() {
                let detune = 1.0 + Double(k) * 0.0015
                let env = 0.12 * (0.6 + 0.4 * sin(2 * .pi * 0.07 * t + Double(k)))
                l += env * sin(2 * .pi * f * detune * t)
                r += env * sin(2 * .pi * f * (2 - detune) * t)
            }
            // faint pulse every 2s
            let pulse = exp(-fmod(t, 2.0) * 2.2) * 0.08 * sin(2 * .pi * 60 * t)
            let fade = min(1.0, t / 1.5) * min(1.0, (seconds - t) / 2.0)
            left[i] = Float((l + pulse) * fade)
            right[i] = Float((r + pulse) * fade)
        }
        try file.write(from: buf)
    }

    // MARK: - video (H.264 via AVAssetWriter)

    static func makeVideo(_ url: URL, seconds: Double, width: Int, height: Int,
                          top: NSColor, bottom: NSColor, title: String, subtitle: String) throws {
        let w = width, h = height, fps = 30
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "ddir", code: 1) }
        writer.startSession(atSourceTime: .zero)

        let total = Int(seconds * Double(fps))
        for frame in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pb = pbOut else { break }
            CVPixelBufferLockBaseAddress(pb, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let ctx {
                drawVideoFrame(ctx, w: w, h: h, t: Double(frame) / Double(fps),
                               top: top, bottom: bottom, title: title, subtitle: subtitle)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        _ = sem.wait(timeout: .now() + 30)
    }

    private static func drawVideoFrame(_ ctx: CGContext, w: Int, h: Int, t: Double,
                                       top: NSColor, bottom: NSColor, title: String, subtitle: String) {
        let rect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w), y: 0), options: [])
        }
        // moving scan grid
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
        ctx.setLineWidth(1)
        let off = CGFloat(fmod(t * 40, 40))
        for x in stride(from: -40 + off, through: CGFloat(w), by: 40) {
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: CGFloat(h)))
        }
        for y in stride(from: -40 + off, through: CGFloat(h), by: 40) {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: CGFloat(w), y: y))
        }
        ctx.strokePath()
        // horizon glow
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))
        ctx.fill(CGRect(x: 0, y: CGFloat(h) * 0.5 - 40, width: CGFloat(w), height: 80))
        // spinning ring
        let cx = CGFloat(w) * 0.5, cy = CGFloat(h) * 0.5
        let r = 120 + 12 * sin(t * 1.3)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
        ctx.setLineWidth(2)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: CGFloat(t * 1.2), endAngle: CGFloat(t * 1.2) + 4.4, clockwise: false)
        ctx.strokePath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.62,
                   startAngle: CGFloat(-t * 1.8), endAngle: CGFloat(-t * 1.8) + 3.1, clockwise: false)
        ctx.strokePath()
        // text (portrait clips get a narrower layout)
        let portrait = CGFloat(h) > CGFloat(w)
        let titleSize: CGFloat = portrait ? 40 : 54
        let titleY = CGFloat(h) * (portrait ? 0.52 : 0.5) - 30
        drawText(ctx, title, size: titleSize, x: 40, y: titleY, alpha: 0.96, tracking: 6)
        drawText(ctx, subtitle, size: portrait ? 12 : 16, x: 42, y: titleY - 38, alpha: 0.62, tracking: 3)
        drawText(ctx, String(format: "T+%05.2f", t), size: 13, x: 42, y: 64, alpha: 0.5, tracking: 3)
        if !portrait {
            drawText(ctx, "ddir · desktop director", size: 12, x: CGFloat(w) - 260, y: 64, alpha: 0.4, tracking: 2)
        }
    }

    private static func drawText(_ ctx: CGContext, _ s: String, size: CGFloat, x: CGFloat, y: CGFloat,
                                 alpha: CGFloat, tracking: CGFloat) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .kern: tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}
