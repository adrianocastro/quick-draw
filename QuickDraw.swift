// Quick Draw — a macOS homage to WinFight (Artematica, Windows 3.1).
// Lives in the menu bar. Every so often a cowboy appears somewhere on your
// screen, calls "Draw!", and shoots you unless you click him first.

import AppKit
import AVFoundation

// MARK: - Settings

enum Difficulty: Int, CaseIterable {
    case greenhorn, gunslinger, legend
    var title: String { ["Greenhorn", "Gunslinger", "Legend"][rawValue] }
    /// Seconds between "Draw!" and the cowboy pulling the trigger.
    var reaction: TimeInterval { [1.3, 0.8, 0.5][rawValue] }
}

enum AmbushWindow: Int, CaseIterable {
    case short, medium, long, marathon
    var title: String { ["Every 1–5 minutes", "Every 5–15 minutes", "Every 15–45 minutes", "Every 30–90 minutes"][rawValue] }
    var range: ClosedRange<TimeInterval> { [60...300, 300...900, 900...2700, 1800...5400][rawValue] }
}

final class Settings {
    private let d = UserDefaults.standard

    init() {
        d.register(defaults: ["timed": true, "difficulty": 1, "window": 1, "wins": 0, "losses": 0])
    }

    var timed: Bool {
        get { d.bool(forKey: "timed") }
        set { d.set(newValue, forKey: "timed") }
    }
    var difficulty: Difficulty {
        get { Difficulty(rawValue: d.integer(forKey: "difficulty")) ?? .gunslinger }
        set { d.set(newValue.rawValue, forKey: "difficulty") }
    }
    var window: AmbushWindow {
        get { AmbushWindow(rawValue: d.integer(forKey: "window")) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "window") }
    }
    var wins: Int {
        get { d.integer(forKey: "wins") }
        set { d.set(newValue, forKey: "wins") }
    }
    var losses: Int {
        get { d.integer(forKey: "losses") }
        set { d.set(newValue, forKey: "losses") }
    }
    /// Fastest winning draw, in milliseconds.
    var best: Int? {
        get { d.object(forKey: "best") as? Int }
        set { d.set(newValue, forKey: "best") }
    }
}

// MARK: - Sound

enum Sound {
    private static let shot = wav(seconds: 0.6) { t, noise, lowpass in
        // A filtered-noise crack over a low thump
        lowpass * 1.6 * exp(-t * 16) + sin(2 * .pi * 55 * t) * exp(-t * 9) * 0.8 + noise * exp(-t * 5) * 0.06
    }
    private static let dryFire = wav(seconds: 0.16) { t, noise, _ in
        // Hammer falling on an empty chamber: two short metallic ticks
        func tick(_ start: Double, _ pitch: Double) -> Double {
            guard t >= start else { return 0 }
            let u = t - start
            return (sin(2 * .pi * pitch * u) * 0.7 + noise * 0.3) * exp(-u * 500)
        }
        return tick(0, 3200) + tick(0.055, 2300) * 0.8
    }
    private static var playing: [NSSound] = []

    static func gunshot() { play(shot) }
    static func click() { play(dryFire) }

    private static func play(_ data: Data) {
        playing.removeAll { !$0.isPlaying }
        guard let sound = NSSound(data: data) else { return }
        playing.append(sound)
        sound.play()
    }

    /// Renders a mono 16-bit WAV from `sample(t, whiteNoise, lowpassedNoise)`.
    private static func wav(seconds: Double, _ sample: (Double, Double, Double) -> Double) -> Data {
        let rate = 44_100
        let count = Int(Double(rate) * seconds)
        var samples = [Int16](repeating: 0, count: count)
        var lowpass = 0.0
        for i in 0..<count {
            let noise = Double.random(in: -1...1)
            lowpass += (noise - lowpass) * 0.35
            let v = max(-1, min(1, sample(Double(i) / Double(rate), noise, lowpass)))
            samples[i] = Int16(v * Double(Int16.max))
        }

        var data = Data()
        func put(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); u32(36 + count * 2); put("WAVE")
        put("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        put("data"); u32(count * 2)
        samples.forEach { s in withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }
}

func western(_ size: CGFloat) -> NSFont {
    NSFont(name: "Rockwell-ExtraBold", size: size)
        ?? NSFont(name: "AmericanTypewriter-Bold", size: size)
        ?? .boldSystemFont(ofSize: size)
}

// MARK: - The cowboy

enum Pose { case standing, drawn, firing, dead }

/// An 8-bit style sprite: each character is one fat pixel. A black outline is
/// added automatically around the art, so the finished sprite is 25×40 pixels,
/// drawn at 2 points per pixel = 50×80.
enum Sprite {
    static let scale: CGFloat = 2

    private static let head = [
        ".......YYYYYYY",
        ".......YYYYYYY",
        ".......yyyyyyy",
        ".YYYYYYYYYYYYYYYYYYY",
        "...YYYYYYYYYYYYYYY",
        ".......SSSSSSS",
        ".......SKSSSKS",
        ".......SSSSSSS",
        ".......SKKKKKS",
        "........SSSSS",
        ".........SSS",
    ]
    private static let holstered = [
        "....CCCKKKCKKKCCC",
        "...CCCCKKKCKKKCCCC",
        "..CC.CCKKKCKKKCC.CC",
        "..CC.CCKKKCKKKCC.CC",
        "..CC.CCKKKCKKKCC.CC",
        "..CC.CCKKKCKKKCC.CC",
        "..CC.MMMMMMMMMMM.CC",
        "..SS.MMMMMMMMMMM.SS",
        "..SS.GGGGGGGGGBL.SS",
        ".....GGGGGGGGGBB",
    ]
    private static let drawn = [
        "....CCCKKKCKKKCCC",
        "...CCCCKKKCKKKCCCCCSLLL",
        "..CC.CCKKKCKKKCC...SL",
        "..CC.CCKKKCKKKCC",
        "..CC.CCKKKCKKKCC",
        "..CC.CCKKKCKKKCC",
        "..CC.MMMMMMMMMMM",
        "..SS.MMMMMMMMMMM",
        "..SS.GGGGGGGGGBB",
        ".....GGGGGGGGGBB",
    ]
    private static let legs = [
        ".....GGGGG.GGGBB",
        ".....GGGGG.GGGBB",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....GGGGG.GGGGG",
        ".....KKKKK.KKKKK",
        ".....KKKKK.KKKKK",
        "....KKKKKK.KKKKKK",
        "....KKKKKK.KKKKKK",
    ]
    private static let flash = [
        "..O...O",
        "...F.F.",
        "OFFWFF.",
        "...F.F.",
        "..O...O",
    ]

    private static let palette: [Character: NSColor] = [
        "Y": NSColor(srgbRed: 0.95, green: 0.80, blue: 0.22, alpha: 1),
        "y": NSColor(srgbRed: 0.62, green: 0.45, blue: 0.10, alpha: 1),
        "S": NSColor(srgbRed: 0.96, green: 0.78, blue: 0.55, alpha: 1),
        "K": NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1),
        "M": NSColor(srgbRed: 0.72, green: 0.08, blue: 0.32, alpha: 1),
        "G": NSColor(srgbRed: 0.72, green: 0.72, blue: 0.76, alpha: 1),
        "B": NSColor(srgbRed: 0.45, green: 0.26, blue: 0.10, alpha: 1),
        "L": NSColor(srgbRed: 0.35, green: 0.35, blue: 0.40, alpha: 1),
        "O": NSColor(srgbRed: 1.00, green: 0.45, blue: 0.05, alpha: 1),
        "F": NSColor(srgbRed: 1.00, green: 0.88, blue: 0.20, alpha: 1),
        "W": .white,
    ]
    private static let checkRed = NSColor(srgbRed: 0.80, green: 0.14, blue: 0.24, alpha: 1)

    typealias Grid = [[Character]]

    private static func grid(_ rows: [String], width: Int = 23, height: Int = 38) -> Grid {
        let padded = rows.map { Array($0.padding(toLength: width, withPad: ".", startingAt: 0)) }
        return Array(repeating: Array(repeating: ".", count: width), count: max(0, height - padded.count)) + padded
    }

    /// Surrounds the art with a one-pixel black outline (and one pixel of margin for it).
    private static func outlined(_ art: Grid) -> Grid {
        let h = art.count + 2, w = art[0].count + 2
        var out = Grid(repeating: Array(repeating: ".", count: w), count: h)
        for r in 0..<art.count { for c in 0..<art[r].count { out[r + 1][c + 1] = art[r][c] } }
        let filled = out
        for r in 0..<h {
            for c in 0..<w where filled[r][c] == "." {
                let touches = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)].contains { rr, cc in
                    rr >= 0 && rr < h && cc >= 0 && cc < w && filled[rr][cc] != "."
                }
                if touches { out[r][c] = "K" }
            }
        }
        return out
    }

    /// Lays the sprite on its side, head to the left.
    private static func rotated(_ g: Grid) -> Grid {
        let h = g.count, w = g[0].count
        return (0..<w).map { r in (0..<h).map { c in g[c][w - 1 - r] } }
    }

    static let standingGrid = outlined(grid(head + holstered + legs))
    static let drawnGrid = outlined(grid(head + drawn + legs))
    static let deadGrid: Grid = {
        var art = grid(head + holstered + legs)
        // Eyes shut for good
        for (r, c) in [(6, 8), (6, 12)] { art[r + 2][c] = "S" }
        for c in 8...12 { art[8][c] = "K" }
        return rotated(outlined(art))
    }()
    static let flashGrid = grid(flash, width: 7, height: 5)

    /// Draws `g` with its bottom-left corner at `origin`.
    static func draw(_ g: Grid, at origin: NSPoint) {
        for (r, row) in g.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                let color: NSColor
                if ch == "C" {
                    color = (r.isMultiple(of: 2) && c.isMultiple(of: 2)) ? .white : checkRed
                } else {
                    color = palette[ch] ?? .magenta
                }
                color.setFill()
                NSRect(x: origin.x + CGFloat(c) * scale, y: origin.y + CGFloat(g.count - 1 - r) * scale,
                       width: scale, height: scale).fill()
            }
        }
    }

    static func size(_ g: Grid) -> NSSize {
        NSSize(width: CGFloat(g[0].count) * scale, height: CGFloat(g.count) * scale)
    }
}

final class CowboyView: NSView {
    /// Room for the 50×80 sprite, its muzzle flash, and lying down 80 wide.
    static let size = NSSize(width: 100, height: 80)
    private static let spriteX: CGFloat = 10

    var pose = Pose.standing { didSet { needsDisplay = true } }

    /// The sprite itself; the rest of the view is margin for the flash and the fall.
    var hitBox: NSRect {
        NSRect(origin: NSPoint(x: frame.minX + Self.spriteX, y: frame.minY), size: Sprite.size(Sprite.standingGrid))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        switch pose {
        case .standing:
            Sprite.draw(Sprite.standingGrid, at: NSPoint(x: Self.spriteX, y: 0))
        case .drawn, .firing:
            Sprite.draw(Sprite.drawnGrid, at: NSPoint(x: Self.spriteX, y: 0))
            if pose == .firing {
                // Just past the barrel tip (sprite column 24, row 13)
                Sprite.draw(Sprite.flashGrid, at: NSPoint(x: Self.spriteX + 48, y: 80 - 2 * 16))
            }
        case .dead:
            Sprite.draw(Sprite.deadGrid, at: .zero)
        }
    }

    // Clicks belong to the overlay, which decides hit or miss.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Overlay

struct BulletHole {
    let center: NSPoint
    let radius: CGFloat
    let cracks: [(angle: CGFloat, length: CGFloat, kink: CGFloat)]

    init(_ center: NSPoint, big: Bool = false) {
        self.center = center
        radius = big ? 18 : 7
        let scale: CGFloat = big ? 4 : 1
        cracks = (0..<Int.random(in: 5...9)).map { _ in
            (CGFloat.random(in: 0..<2 * .pi), CGFloat.random(in: 12...32) * scale, CGFloat.random(in: -0.35...0.35))
        }
    }

    func draw() {
        for crack in cracks {
            let mid = NSPoint(x: center.x + cos(crack.angle + crack.kink) * crack.length * 0.5,
                              y: center.y + sin(crack.angle + crack.kink) * crack.length * 0.5)
            let end = NSPoint(x: center.x + cos(crack.angle) * crack.length,
                              y: center.y + sin(crack.angle) * crack.length)
            for (color, width, offset) in [(NSColor(white: 0, alpha: 0.6), CGFloat(2.2), CGFloat(0)),
                                           (NSColor(white: 1, alpha: 0.75), CGFloat(1), CGFloat(1))] {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: center.x + offset, y: center.y + offset))
                p.line(to: NSPoint(x: mid.x + offset, y: mid.y + offset))
                p.line(to: NSPoint(x: end.x + offset, y: end.y + offset))
                p.lineWidth = width
                color.setStroke()
                p.stroke()
            }
        }
        let rim = NSRect(x: center.x - radius - 3, y: center.y - radius - 3, width: (radius + 3) * 2, height: (radius + 3) * 2)
        NSColor(white: 0.55, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: rim).fill()
        NSColor(white: 0.03, alpha: 1).setFill()
        NSBezierPath(ovalIn: rim.insetBy(dx: 3, dy: 3)).fill()
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayView: NSView {
    weak var game: Game?
    var holes: [BulletHole] = []
    /// The cowboy's sprite rect while he is calling "Draw!".
    var bubble: NSRect? { didSet { needsDisplay = true } }
    var flash: CGFloat = 0 { didSet { needsDisplay = true } }
    private let banner = BannerView()

    /// Shows the end-of-duel message on top of everything, clear of the cowboy.
    func announce(_ title: String, _ detail: String, avoiding cowboy: NSRect?) {
        banner.frame = bounds
        if banner.superview == nil { addSubview(banner) }
        banner.title = title
        banner.detail = detail
        // Upper third if he's low on screen, lower third if he's high.
        banner.baseline = (cowboy?.midY ?? 0) < bounds.midY ? bounds.height * 0.68 : bounds.height * 0.28
        banner.needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        game?.fire(at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { game?.flee() } else { super.keyDown(with: event) }
    }

    func addHole(_ p: NSPoint, big: Bool = false) {
        holes.append(BulletHole(p, big: big))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fully transparent pixels let clicks fall through to the app below,
        // so the overlay keeps a barely-there tint to catch every shot.
        NSColor(white: 0, alpha: 0.012).setFill()
        bounds.fill()
        if flash > 0 {
            NSColor(calibratedRed: 0.75, green: 0, blue: 0, alpha: flash).setFill()
            bounds.fill(using: .sourceOver)
        }
        holes.forEach { $0.draw() }
        if let bubble { drawBubble(beside: bubble) }
    }

    private func drawBubble(beside sprite: NSRect) {
        let text = NSAttributedString(string: "DRAW!", attributes: [
            .font: western(42),
            .foregroundColor: NSColor(calibratedRed: 0.6, green: 0.08, blue: 0.05, alpha: 1),
        ])
        let size = text.size()
        let width = size.width + 36, height = size.height + 18
        // Up and to the right by default; flip left or down when he's near an edge.
        let right = sprite.maxX + 8 + width <= bounds.maxX - 8
        let tip = NSPoint(x: right ? sprite.maxX - 8 : sprite.minX + 8, y: sprite.maxY - 10)
        let above = tip.y + 22 + height <= bounds.maxY - 8
        let box = NSRect(x: right ? tip.x + 16 : tip.x - 16 - width,
                         y: above ? tip.y + 22 : tip.y - 10 - height,
                         width: width, height: height)
        let baseX = right ? box.minX + 14 : box.maxX - 38
        let baseY = above ? box.minY + 2 : box.maxY - 2
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: baseX, y: baseY))
        tail.line(to: tip)
        tail.line(to: NSPoint(x: baseX + 24, y: baseY))
        tail.close()
        let path = NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16)
        path.append(tail)
        path.windingRule = .nonZero
        NSColor(calibratedRed: 1, green: 0.97, blue: 0.88, alpha: 1).setFill()
        path.fill()
        NSColor.black.setStroke()
        path.lineWidth = 3
        path.stroke()
        text.draw(at: NSPoint(x: box.minX + 18, y: box.minY + 9))
    }
}

final class BannerView: NSView {
    var title = ""
    var detail = ""
    var baseline: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        func centered(_ s: String, size: CGFloat, color: NSColor, y: CGFloat) {
            func text(_ size: CGFloat) -> NSAttributedString {
                NSAttributedString(string: s, attributes: [
                    .font: western(size), .foregroundColor: color,
                    .strokeColor: NSColor.black, .strokeWidth: -3.5, .shadow: shadow,
                ])
            }
            var a = text(size)
            let room = bounds.width - 80
            if a.size().width > room { a = text(size * room / a.size().width) }
            a.draw(at: NSPoint(x: bounds.midX - a.size().width / 2, y: y))
        }
        centered(title, size: 76, color: NSColor(calibratedRed: 1, green: 0.84, blue: 0.3, alpha: 1), y: baseline)
        centered(detail, size: 26, color: .white, y: baseline - 50)
    }
}

// MARK: - Game

final class Game {
    private let settings: Settings
    var onRecordChange: (() -> Void)?

    private enum Phase { case idle, standoff, draw, over }
    private var phase = Phase.idle
    private var loaded = false
    private var overlays: [OverlayWindow] = []
    private var cowboy: CowboyView?
    private weak var arena: OverlayView?
    private var drawTime: CFTimeInterval = 0
    private var ambush: Timer?
    private var timers: [Timer] = []
    private let speech = AVSpeechSynthesizer()

    init(settings: Settings) { self.settings = settings }

    var inDuel: Bool { phase != .idle }

    // MARK: Scheduling

    func scheduleAmbush(after delay: TimeInterval? = nil) {
        ambush?.invalidate()
        ambush = nil
        guard settings.timed else { return }
        let wait = delay ?? .random(in: settings.window.range)
        ambush = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in self?.ambushDue() }
    }

    private func ambushDue() {
        // No fair shooting someone who isn't at their desk: wait for them to come back.
        if screenLocked || idleSeconds > 120 || phase != .idle {
            scheduleAmbush(after: 30)
        } else {
            startDuel()
        }
    }

    private var screenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private var idleSeconds: TimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: The duel

    func startDuel() {
        guard phase == .idle else { return }
        ambush?.invalidate()
        phase = .standoff
        loaded = true

        let screens = NSScreen.screens
        guard let target = screens.randomElement() else { phase = .idle; return }
        for screen in screens {
            let window = OverlayWindow(screen: screen)
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.game = self
            window.contentView = view
            window.orderFrontRegardless()
            overlays.append(window)
            if screen == target {
                arena = view
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
        }
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }

        let visible = target.visibleFrame.offsetBy(dx: -target.frame.minX, dy: -target.frame.minY)
        let size = CowboyView.size
        // Anywhere in the usable area (menu bar and Dock excluded), edge to edge.
        let x = CGFloat.random(in: visible.minX ... max(visible.minX, visible.maxX - size.width))
        let y = CGFloat.random(in: visible.minY ... max(visible.minY, visible.maxY - size.height))
        let cowboy = CowboyView(frame: NSRect(origin: NSPoint(x: x, y: y), size: size))
        cowboy.alphaValue = 0
        arena?.addSubview(cowboy)
        self.cowboy = cowboy
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            cowboy.animator().alphaValue = 1
        }

        after(.random(in: 0.6...1.8)) { [weak self] in self?.callDraw() }
    }

    private func callDraw() {
        guard phase == .standoff, let cowboy, let arena else { return }
        phase = .draw
        drawTime = CACurrentMediaTime()
        arena.bubble = cowboy.hitBox

        let utterance = AVSpeechUtterance(string: "Draw!")
        utterance.rate = 0.45
        utterance.pitchMultiplier = 0.6
        speech.speak(utterance)

        let reaction = settings.difficulty.reaction
        after(reaction * 0.55) { [weak self] in
            if self?.phase == .draw { self?.cowboy?.pose = .drawn }
        }
        after(reaction) { [weak self] in self?.cowboyFires() }
    }

    func fire(at point: NSPoint, in view: OverlayView) {
        // One bullet per duel, and dead men don't shoot.
        guard loaded, phase == .standoff || phase == .draw else {
            Sound.click()
            return
        }
        loaded = false
        Sound.gunshot()
        let hit = view === arena && (cowboy?.hitBox.contains(point) ?? false)
        if !hit { view.addHole(point) }
        if phase == .standoff {
            coward(hit: hit)
        } else if hit {
            win()
        }
    }

    private func win() {
        cancelTimers()
        phase = .over
        speech.stopSpeaking(at: .immediate)
        arena?.bubble = nil
        cowboy?.pose = .dead

        settings.wins += 1
        let ms = Int((CACurrentMediaTime() - drawTime) * 1000)
        let record = settings.best.map { ms < $0 } ?? true
        if record { settings.best = ms }
        let quip = record ? "Fastest gun in the West." : ms < 400 ? "Lightning." : "Not bad, partner."
        arena?.announce("GOT HIM!", "\(ms) ms — \(quip)", avoiding: cowboy?.frame)
        onRecordChange?()
        after(2.6) { [weak self] in self?.endDuel() }
    }

    /// Firing before he calls "Draw!" is a loss, hit or miss.
    private func coward(hit: Bool) {
        cancelTimers()
        phase = .over
        arena?.bubble = nil
        if hit { cowboy?.pose = .dead }

        settings.losses += 1
        let detail = hit ? "Shot him before he called it. That's a loss." : "Fired before he called it. That's a loss."
        arena?.announce("COWARD!", detail, avoiding: cowboy?.frame)
        onRecordChange?()
        after(2.6) { [weak self] in self?.endDuel() }
    }

    private func cowboyFires() {
        guard phase == .draw, let cowboy, let arena else { return }
        cancelTimers()
        phase = .over
        cowboy.pose = .firing
        Sound.gunshot()
        arena.bubble = nil
        // He shoots at you: the hole lands wherever your cursor is.
        let mouse = NSEvent.mouseLocation
        if let window = overlays.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let view = window.contentView as? OverlayView {
            view.addHole(NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY), big: true)
        } else {
            arena.addHole(NSPoint(x: arena.bounds.midX, y: arena.bounds.midY), big: true)
        }
        arena.announce("YOU'RE DEAD, PARTNER", "Too slow on the draw.", avoiding: cowboy.frame)
        settings.losses += 1
        onRecordChange?()

        let views = overlays.compactMap { $0.contentView as? OverlayView }
        views.forEach { $0.flash = 0.5 }
        var step = 0
        timers.append(Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            step += 1
            views.forEach { $0.flash = max(0, 0.5 - CGFloat(step) / 50) }
            if step >= 25 { timer.invalidate() }
        })
        after(0.12) { cowboy.pose = .drawn }
        after(3.0) { [weak self] in self?.endDuel() }
    }

    func flee() {
        guard phase == .standoff || phase == .draw else { return }
        cancelTimers()
        phase = .over
        speech.stopSpeaking(at: .immediate)
        arena?.bubble = nil
        arena?.announce("YELLOW-BELLIED", "You ran. He'll be back.", avoiding: cowboy?.frame)
        after(1.4) { [weak self] in self?.endDuel() }
    }

    private func endDuel() {
        cancelTimers()
        let windows = overlays
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            windows.forEach { $0.orderOut(nil) }
        })
        overlays = []
        cowboy = nil
        phase = .idle
        NSApp.hide(nil) // hand focus back to whatever you were doing
        scheduleAmbush()
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        timers.append(Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in block() })
    }

    private func cancelTimers() {
        timers.forEach { $0.invalidate() }
        timers = []
    }
}

// MARK: - Menu bar

final class MenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var game = Game(settings: settings)
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "Quick Draw")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        game.scheduleAmbush()
        if CommandLine.arguments.contains("--fight") { game.startDuel() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let fightNow = MenuItem("Fight Now", key: "f") { [weak self] in
            DispatchQueue.main.async { self?.game.startDuel() }
        }
        fightNow.isEnabled = !game.inDuel
        menu.addItem(fightNow)
        menu.addItem(MenuItem("Timed Fight (ambush me)", checked: settings.timed) { [weak self] in
            guard let self else { return }
            settings.timed.toggle()
            game.scheduleAmbush()
        })

        let windowMenu = NSMenu()
        for option in AmbushWindow.allCases {
            windowMenu.addItem(MenuItem(option.title, checked: option == settings.window) { [weak self] in
                self?.settings.window = option
                self?.game.scheduleAmbush()
            })
        }
        let windowItem = NSMenuItem(title: "Ambush Frequency", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)

        let difficultyMenu = NSMenu()
        for option in Difficulty.allCases {
            let title = "\(option.title) (\(Int(option.reaction * 1000)) ms)"
            difficultyMenu.addItem(MenuItem(title, checked: option == settings.difficulty) { [weak self] in
                self?.settings.difficulty = option
            })
        }
        let difficultyItem = NSMenuItem(title: "Difficulty", action: nil, keyEquivalent: "")
        difficultyItem.submenu = difficultyMenu
        menu.addItem(difficultyItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Record: \(settings.wins) won · \(settings.losses) lost", action: nil, keyEquivalent: "")
        if let best = settings.best {
            menu.addItem(withTitle: "Fastest draw: \(best) ms", action: nil, keyEquivalent: "")
        }
        menu.addItem(MenuItem("Reset Record") { [weak self] in
            self?.settings.wins = 0
            self?.settings.losses = 0
            self?.settings.best = nil
        })
        menu.addItem(.separator())
        menu.addItem(MenuItem("Quit Quick Draw", key: "q") { NSApp.terminate(nil) })
    }
}

// MARK: - Icon rendering (used by build.sh)

func renderIcon(to path: String) {
    let side = 1024
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.25, alpha: 1),
               ending: NSColor(calibratedRed: 0.97, green: 0.86, blue: 0.6, alpha: 1))?.draw(in: tile, angle: -90)
    tile.addClip()
    let t = NSAffineTransform()
    t.translateX(by: 512 - 225, yBy: 152)
    t.scale(by: 9)
    t.concat()
    NSGraphicsContext.current?.shouldAntialias = false
    Sprite.draw(Sprite.drawnGrid, at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
    renderIcon(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
