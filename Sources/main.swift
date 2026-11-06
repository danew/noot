import AppKit
import Carbon.HIToolbox

// MARK: - Config

/// Global shortcut: ⌃⌥N (Control + Option + N)
let hotKeyCode = UInt32(kVK_ANSI_N)
let hotKeyModifiers = UInt32(controlKey | optionKey)

let padding: CGFloat = 8
let fontSize: CGFloat = 13
let defaultSize = NSSize(width: 320, height: 200)

// MARK: - Note window

let cornerRadius: CGFloat = 10
let handleSize: CGFloat = 30   // corner resize zones
let edgeSize: CGFloat = 8      // edge resize strips (= padding, so they don't cover text)

/// Rounded, theme-aware background with a hairline border.
final class ContainerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// Hollow dot at the top centre; fills on hover and drags the window.
final class DragDot: NSView {
    private var hovering = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func cursorUpdate(with e: NSEvent) { NSCursor.openHand.set() }
    override func mouseDown(with e: NSEvent) {
        guard let w = window as? NoteWindow else { return }
        if e.clickCount == 2 { w.toggleFloat(); return }
        NSCursor.closedHand.set()
        trackMouse(in: w) { start, dx, dy in start.offsetBy(dx: dx, dy: dy) }
        NSCursor.openHand.set()
    }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 7
        let r = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let path = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        let color = NSColor.secondaryLabelColor
        // Pinned (always on top): solid fill. Hover while unpinned: faint fill.
        let pinned = window?.level == .floating
        if pinned { color.setFill(); path.fill() }
        else if hovering { color.withAlphaComponent(0.4).setFill(); path.fill() }
        color.setStroke(); path.lineWidth = 1; path.stroke()
    }
}

/// Invisible hit area that resizes the window from a corner or an edge.
final class ResizeHandle: NSView {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
    }
    let edges: Edges

    init(_ edges: Edges) { self.edges = edges; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func cursorUpdate(with e: NSEvent) { cursor.set() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    private var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let pos: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]: pos = .topLeft
            case [.top, .right]: pos = .topRight
            case [.bottom, .left]: pos = .bottomLeft
            case [.bottom, .right]: pos = .bottomRight
            case .top: pos = .top
            case .bottom: pos = .bottom
            case .left: pos = .left
            default: pos = .right
            }
            return .frameResize(position: pos, directions: .all)
        }
        if edges == .left || edges == .right { return .resizeLeftRight }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        return .crosshair
    }

    override func mouseDown(with e: NSEvent) {
        guard let w = window else { return }
        let minW = w.minSize.width, minH = w.minSize.height
        let edges = self.edges
        trackMouse(in: w) { start, dx, dy in
            var f = start
            if edges.contains(.right) {
                f.size.width = max(minW, start.width + dx)
            } else if edges.contains(.left) {
                f.size.width = max(minW, start.width - dx)
                f.origin.x = start.maxX - f.width
            }
            if edges.contains(.top) {
                f.size.height = max(minH, start.height + dy)
            } else if edges.contains(.bottom) {
                f.size.height = max(minH, start.height - dy)
                f.origin.y = start.maxY - f.height
            }
            return f
        }
    }
}

/// Runs a mouse-tracking loop from the current mouseDown until mouseUp, setting the
/// window frame to whatever `frameFor(startFrame, dx, dy)` returns. Using our own
/// loop (rather than performDrag / mouseDragged overrides) means drag events can't
/// leak to the wrong view or arrive without a matching mouseDown.
func trackMouse(in w: NSWindow, frameFor: @escaping (NSRect, CGFloat, CGFloat) -> NSRect) {
    let startFrame = w.frame
    let startMouse = NSEvent.mouseLocation
    w.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
        guard let event else { return }
        if event.type == .leftMouseUp { stop.pointee = true; return }
        let m = NSEvent.mouseLocation
        let f = frameFor(startFrame, m.x - startMouse.x, m.y - startMouse.y)
        guard f.width >= w.minSize.width, f.height >= w.minSize.height else { return }
        w.setFrame(f, display: true)
    }
}

final class NoteWindow: NSWindow {
    init(at origin: NSPoint) {
        super.init(
            contentRect: NSRect(origin: origin, size: defaultSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 80, height: 40)
        collectionBehavior = [.moveToActiveSpace]
        tabbingMode = .disallowed

        let container = ContainerView(frame: NSRect(origin: .zero, size: defaultSize))

        let scroll = NSTextView.scrollableTextView()
        scroll.frame = container.bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let tv = scroll.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = .textColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: padding, height: padding)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        container.addSubview(scroll)

        // Resize handles overlay the text, which still fills the window.
        // Corners are handleSize square; edges are edgeSize thick strips between them.
        let b = container.bounds
        let c = handleSize, e = edgeSize
        let handles: [(ResizeHandle.Edges, NSRect, NSView.AutoresizingMask)] = [
            (.left,             NSRect(x: 0, y: c, width: e, height: b.height - 2 * c),          [.maxXMargin, .height]),
            (.right,            NSRect(x: b.maxX - e, y: c, width: e, height: b.height - 2 * c), [.minXMargin, .height]),
            (.bottom,           NSRect(x: c, y: 0, width: b.width - 2 * c, height: e),           [.maxYMargin, .width]),
            (.top,              NSRect(x: c, y: b.maxY - e, width: b.width - 2 * c, height: e),  [.minYMargin, .width]),
            ([.bottom, .left],  NSRect(x: 0, y: 0, width: c, height: c),                         [.maxXMargin, .maxYMargin]),
            ([.bottom, .right], NSRect(x: b.maxX - c, y: 0, width: c, height: c),                [.minXMargin, .maxYMargin]),
            ([.top, .left],     NSRect(x: 0, y: b.maxY - c, width: c, height: c),                [.maxXMargin, .minYMargin]),
            ([.top, .right],    NSRect(x: b.maxX - c, y: b.maxY - c, width: c, height: c),       [.minXMargin, .minYMargin]),
        ]
        for (edges, frame, mask) in handles {
            let h = ResizeHandle(edges)
            h.frame = frame
            h.autoresizingMask = mask
            container.addSubview(h)
        }

        // Drag dot, top centre.
        dot = DragDot(frame: NSRect(x: b.midX - 12, y: b.maxY - 14, width: 24, height: 14))
        dot.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        container.addSubview(dot)

        contentView = container
        initialFirstResponder = tv
    }

    private var dot: DragDot!

    func toggleFloat() {
        level = level == .floating ? .normal : .floating
        dot.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Borderless windows aren't .closable, so AppKit disables performClose:.
    // ⌘W goes through this instead.
    @objc func closeNote(_ sender: Any?) { close() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMainMenu()
        buildStatusItem()
        registerHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    @objc func newNote() {
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - defaultSize.width / 2, y: mouse.y - defaultSize.height / 2)
        let w = NoteWindow(at: origin)
        w.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            w.setFrame(w.constrainFrameRect(w.frame, to: screen), display: false)
        }
        windows.append(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // Ephemeral: closing drops the window and its text for good.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
    }

    @objc func toggleFloat(_ sender: NSMenuItem) {
        guard let w = NSApp.keyWindow else { return }
        (w as? NoteWindow)?.toggleFloat()
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "noot")
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note  (⌃⌥N)", action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit noot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit noot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Close", action: #selector(NoteWindow.closeNote(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f").tag =
            Int(NSFindPanelAction.showFindPanel.rawValue)
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Float on Top", action: #selector(toggleFloat(_:)), keyEquivalent: "t").target = self
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.newNote() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x6E6F6F74), id: 1) // 'noot'
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
