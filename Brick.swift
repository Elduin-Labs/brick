// Brick: a little brick person who lives on your screen and talks with you.
// He floats above everything and never gets in the way of your mouse.
// Click the brick in the menu bar to talk to him. His answers come from Claude.
import Cocoa

// MARK: Brick's brain

enum Brain {
    static let keychainService = "claude-anthropic"
    static let model = "claude-haiku-4-5-20251001"

    static let personality = """
    You are Brick, a friendly little brick person who lives on a kid's computer screen. \
    The kid loves building Minecraft mods and is very good at knowing what they want things to do. \
    Talk in short, simple, friendly sentences, three at most, with plain words. \
    You can look things up on the internet with web search, so use it whenever the kid asks about \
    facts, news, games, Minecraft, how things work, or anything you are not sure about. \
    Then answer in your own simple words. Never read out web addresses. \
    Only use kid-friendly sources, and if a search turns up something scary or too grown-up, skip it. \
    Be fun, curious and encouraging. You love building things, and you make the odd brick joke. \
    Never ask for or repeat private things like a last name, school, town, address, phone number, \
    email or passwords. If the kid shares something like that, kindly say that is one for a grown-up. \
    If anything gets scary, mean or too grown-up, gently change the subject and say a grown-up can help. \
    You can't see the screen and you can't control the computer, so don't pretend you can. \
    If you can't find something out, say so honestly instead of guessing.
    """

    /// The key comes from the environment, or from the login Keychain (see set-key.sh).
    static func apiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty { return key }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-w", "-s", keychainService, "-a", NSUserName()]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }

    /// Pulls Brick's words out of Claude's answer. When he searched the web, the answer is mixed in with
    /// the search steps, so only the words after the last search result count.
    static func answer(from json: [String: Any]) -> String? {
        guard let content = json["content"] as? [[String: Any]] else { return nil }
        var words = ""
        for block in content {
            switch block["type"] as? String {
            case "web_search_tool_result": words = ""
            case "text": words += (block["text"] as? String) ?? ""
            default: break
            }
        }
        let line = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// Asks Claude for Brick's next line. `done` gets nil if anything goes wrong.
    static func reply(to messages: [[String: String]], key: String, done: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60   // looking things up on the web takes a moment
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "system": personality,
            "messages": messages,
            // Brick's window on the internet. Claude searches the web itself, a few times at most.
            "tools": [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var text: String?
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                text = answer(from: json)
            }
            DispatchQueue.main.async { done(text) }
        }.resume()
    }
}

// MARK: Brick on screen

final class BrickView: NSView {
    private let brickColor = NSColor(calibratedRed: 0.76, green: 0.30, blue: 0.20, alpha: 1)
    private let edgeColor = NSColor(calibratedRed: 0.38, green: 0.12, blue: 0.08, alpha: 1)
    private let mortar = NSColor(calibratedRed: 0.96, green: 0.88, blue: 0.80, alpha: 0.55)

    private var tick = 0
    private var talkingLeft = 0     // ticks of mouth-moving left
    private var bubbleLeft = 0      // ticks the speech bubble stays up
    private var bubbleText: String?
    private var thinking = false

    private let ground: CGFloat = 6
    private let bubbleWidth: CGFloat = 270

    override var isFlipped: Bool { false }

    func say(_ text: String) {
        thinking = false
        bubbleText = text
        talkingLeft = min(300, text.count * 4)
        bubbleLeft = 360 + text.count * 5
    }

    func think() {
        thinking = true
        bubbleText = nil
        bubbleLeft = 0
        talkingLeft = 0
    }

    func step() {
        tick += 1
        if talkingLeft > 0 { talkingLeft -= 1 }
        if bubbleLeft > 0 {
            bubbleLeft -= 1
            if bubbleLeft == 0 { bubbleText = nil }
        }
        needsDisplay = true
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        dirtyRect.fill(using: .clear)

        let t = CGFloat(tick)
        let talking = talkingLeft > 0
        let x = bounds.width - 120
        let bob = sin(t * 0.05) * 1.5 + (talking ? abs(sin(t * 0.3)) * 2 : 0)

        // legs
        let legs = NSBezierPath()
        legs.lineWidth = 5
        legs.lineCapStyle = .round
        for side: CGFloat in [-1, 1] {
            legs.move(to: NSPoint(x: x + side * 11, y: ground + 18))
            legs.line(to: NSPoint(x: x + side * 11, y: ground + 3))
            legs.line(to: NSPoint(x: x + side * 11 + side * 6, y: ground + 3))
        }
        edgeColor.setStroke()
        legs.stroke()

        // body: one big brick with the mortar lines showing
        let body = NSRect(x: x - 24, y: ground + 16 + bob, width: 48, height: 64)
        let shape = NSBezierPath(roundedRect: body, xRadius: 5, yRadius: 5)
        brickColor.setFill()
        shape.fill()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let joints = NSBezierPath()
        joints.lineWidth = 2
        for row in 1..<4 {
            let y = body.minY + CGFloat(row) * 16
            joints.move(to: NSPoint(x: body.minX, y: y))
            joints.line(to: NSPoint(x: body.maxX, y: y))
        }
        for row in 0..<4 {
            let y0 = body.minY + CGFloat(row) * 16
            let offsets: [CGFloat] = row % 2 == 0 ? [0.5] : [0.25, 0.75]
            for o in offsets {
                joints.move(to: NSPoint(x: body.minX + body.width * o, y: y0))
                joints.line(to: NSPoint(x: body.minX + body.width * o, y: y0 + 16))
            }
        }
        mortar.setStroke()
        joints.stroke()
        NSGraphicsContext.restoreGraphicsState()

        edgeColor.setStroke()
        shape.lineWidth = 3
        shape.stroke()

        // arms: they swing a little, and the right one waves while he talks
        let arms = NSBezierPath()
        arms.lineWidth = 5
        arms.lineCapStyle = .round
        let shoulderY = body.minY + 40
        arms.move(to: NSPoint(x: body.minX, y: shoulderY))
        arms.line(to: NSPoint(x: body.minX - 12, y: shoulderY - 14 + sin(t * 0.05) * 2))
        arms.move(to: NSPoint(x: body.maxX, y: shoulderY))
        if talking {
            arms.line(to: NSPoint(x: body.maxX + 12, y: shoulderY + 10 + sin(t * 0.3) * 8))
        } else {
            arms.line(to: NSPoint(x: body.maxX + 12, y: shoulderY - 14 - sin(t * 0.05) * 2))
        }
        edgeColor.setStroke()
        arms.stroke()

        drawFace(in: body, talking: talking)

        if thinking {
            drawBubble(text: String(repeating: ".", count: 1 + Int(tick / 20) % 3), above: body, size: 30)
        } else if let text = bubbleText {
            drawBubble(text: text, above: body, size: 15)
        }
    }

    private func drawFace(in body: NSRect, talking: Bool) {
        let eyeY = body.minY + 46
        let blink = tick % 240 < 8
        let look: CGFloat = thinking ? 3 : 0   // eyes look up while he thinks

        for side: CGFloat in [-1, 1] {
            let cx = body.midX + side * 10
            if blink {
                let lid = NSBezierPath()
                lid.lineWidth = 2.5
                lid.lineCapStyle = .round
                lid.move(to: NSPoint(x: cx - 5, y: eyeY))
                lid.line(to: NSPoint(x: cx + 5, y: eyeY))
                NSColor.black.setStroke()
                lid.stroke()
            } else {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: cx - 6, y: eyeY - 6, width: 12, height: 12)).fill()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: cx - 3, y: eyeY - 3 + look, width: 6, height: 6)).fill()
            }
        }

        let mouthY = body.minY + 24
        if talking {
            let open = 3 + abs(sin(CGFloat(tick) * 0.5)) * 7
            NSColor(calibratedRed: 0.2, green: 0.03, blue: 0.03, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: body.midX - 7, y: mouthY - open / 2, width: 14, height: open)).fill()
        } else {
            let smile = NSBezierPath()
            smile.lineWidth = 2.5
            smile.lineCapStyle = .round
            smile.move(to: NSPoint(x: body.midX - 9, y: mouthY + 2))
            smile.curve(to: NSPoint(x: body.midX + 9, y: mouthY + 2),
                        controlPoint1: NSPoint(x: body.midX - 5, y: mouthY - 8),
                        controlPoint2: NSPoint(x: body.midX + 5, y: mouthY - 8))
            NSColor.black.setStroke()
            smile.stroke()
        }
    }

    private func drawBubble(text: String, above body: NSRect, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: size > 20 ? .heavy : .medium),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: bubbleWidth - 24, height: 400),
            options: [.usesLineFragmentOrigin], attributes: attributes)
        let width = min(bubbleWidth, ceil(measured.width) + 24)
        let height = ceil(measured.height) + 20

        let left = max(10, min(bounds.width - width - 10, body.midX - width / 2))
        let rect = NSRect(x: left, y: body.maxY + 22, width: width, height: height)

        let bubble = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let tailX = max(rect.minX + 18, min(rect.maxX - 18, body.midX))
        bubble.move(to: NSPoint(x: tailX - 8, y: rect.minY))
        bubble.line(to: NSPoint(x: body.midX, y: body.maxY + 6))
        bubble.line(to: NSPoint(x: tailX + 8, y: rect.minY))
        NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
        bubble.fill()
        NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
        bubble.lineWidth = 2
        bubble.stroke()

        (text as NSString).draw(
            with: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: width - 24, height: height - 20),
            options: [.usesLineFragmentOrigin], attributes: attributes)
    }
}

// MARK: the app

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: BrickView!
    var timer: Timer?
    var statusItem: NSStatusItem!

    /// What has been said so far. It lives only in memory and is gone when Brick quits.
    var history: [[String: String]] = []
    var waiting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame

        window = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true   // the mouse goes straight through him
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        view = BrickView(frame: NSRect(origin: .zero, size: area.size))
        window.contentView = view
        window.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.view.step()
        }

        // A little brick in the menu bar: this is how you talk to him, and how you say goodbye.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧱"
        let menu = NSMenu()
        let talkItem = NSMenuItem(title: "Talk to Brick…", action: #selector(talk), keyEquivalent: "t")
        talkItem.target = self
        menu.addItem(talkItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Brick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        view.say("Hi! I'm Brick. Click the 🧱 at the top and pick Talk to Brick!")
    }

    @objc func talk() {
        guard !waiting else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Talk to Brick"
        alert.informativeText = "What do you want to say?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Say it")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { ask(text) }
    }

    private func ask(_ text: String) {
        guard let key = Brain.apiKey() else {
            view.say("I need a grown-up to give me my brain! Ask them to run set-key.sh.")
            return
        }
        history.append(["role": "user", "content": text])
        // Keep the last few lines, and always start with something the kid said.
        while !history.isEmpty && (history.count > 20 || history[0]["role"] != "user") { history.removeFirst() }
        waiting = true
        view.think()

        Brain.reply(to: history, key: key) { [weak self] line in
            guard let self else { return }
            self.waiting = false
            if let line {
                self.history.append(["role": "assistant", "content": line])
                self.view.say(line)
            } else {
                self.history.removeLast()   // so the next try starts clean
                self.view.say("Hmm, my brain got fuzzy. Try again!")
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
