import AppKit
import SwiftUI

@main
@MainActor
enum RelayApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = RelayAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class RelayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?(); orderOut(nil) }
}

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    private let model = RelayModel()
    private let hotKey = HotKeyController()
    private var statusItem: NSStatusItem?
    private var panel: RelayPanel?
    private var shortcutItems: [NSMenuItem] = []
    private var isTerminating = false
    private var keyMonitor: Any?
    /// Distance of the panel's top edge from the top of the screen, as a fraction of usable height.
    private let topFraction: CGFloat = 0.14

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = WhooshIdentity.icon(size: 256)
        configureApplicationMenu()
        hotKey.onPress = { [weak self] in
            self?.model.shortcutActivationCount += 1
            self?.showOverlay()
        }
        configureStatusItem()
        installKeyMonitor()
        let saved = UserDefaults.standard.string(forKey: "relayShortcut")
            .flatMap(HotKeyController.Shortcut.init(rawValue:)) ?? .commandShiftSpace
        if hotKey.register(saved) {
            model.shortcutLabel = saved.label
        } else {
            model.shortcutLabel = "Menu bar"
            model.shortcutNotice = "That shortcut is in use. Open Whoosh from the menu bar and choose another shortcut."
        }
        model.shortcutDiagnostic = hotKey.diagnostic
        updateShortcutChecks()
        FileHandle.standardError.write(Data("Whoosh: global hotkey \(model.shortcutLabel) registered=\(hotKey.selected != nil) [\(hotKey.diagnostic)]\n".utf8))
        showOverlay()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOverlay()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = WhooshIdentity.icon(size: 20, template: true)
        let menu = NSMenu()
        let show = NSMenuItem(title: "Open Whoosh", action: #selector(showOverlay), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let shortcuts = NSMenu()
        for shortcut in HotKeyController.Shortcut.allCases {
            let option = NSMenuItem(title: shortcut.label, action: #selector(changeShortcut(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = shortcut.rawValue
            shortcuts.addItem(option)
            shortcutItems.append(option)
        }
        let shortcutMenu = NSMenuItem(title: "Global shortcut", action: nil, keyEquivalent: "")
        shortcutMenu.submenu = shortcuts
        menu.addItem(shortcutMenu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Whoosh", action: #selector(quitRelay), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func configureApplicationMenu() {
        // Preserve standard text editing shortcuts without creating an empty Settings scene.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Whoosh")
        let quit = NSMenuItem(title: "Quit Whoosh", action: #selector(quitRelay), keyEquivalent: "q")
        quit.target = self
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func changeShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shortcut = HotKeyController.Shortcut(rawValue: raw) else { return }
        if hotKey.register(shortcut) {
            UserDefaults.standard.set(shortcut.rawValue, forKey: "relayShortcut")
            model.shortcutLabel = shortcut.label
            model.shortcutNotice = nil
        } else {
            if let restored = hotKey.selected {
                model.shortcutLabel = restored.label
                model.shortcutNotice = "\(shortcut.label) is unavailable. The previous shortcut was restored."
            } else {
                model.shortcutLabel = "Menu bar"
                model.shortcutNotice = "The shortcut is unavailable. Open Whoosh from the menu bar and choose another shortcut."
            }
            showOverlay()
        }
        model.shortcutDiagnostic = hotKey.diagnostic
        updateShortcutChecks()
    }

    private func updateShortcutChecks() {
        for item in shortcutItems {
            item.state = (item.representedObject as? String) == hotKey.selected?.rawValue ? .on : .off
        }
    }

    @objc func showOverlay() {
        // A fresh hotkey press always starts a new handoff, never the previous one's result screen.
        if model.stage == .complete || model.stage == .review { model.startAgain() }
        // Capture foreground context BEFORE Whoosh becomes active. It suggests a source app, never a thread.
        model.suggestSource(from: NSWorkspace.shared.frontmostApplication)
        model.refreshForPresentation()
        if panel == nil { panel = makePanel() }
        model.nativeSearch = ""
        model.errorMessage = nil
        model.ensureHighlight()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        pinTopEdge()
    }

    private func makePanel() -> RelayPanel {
        let window = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.onCancel = { [weak self] in self?.model.cancelSourceRead(); self?.model.cancelPreparation() }
        model.onDestinationOpened = { [weak self] in self?.hideOverlay() }
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true    // A clear borderless window casts its shadow from the content's alpha, so it follows the rounded card
        window.level = .floating
        // Normally the panel dismisses when you click away; BLINK_DEBUG_PIN keeps it up for headless UI checks.
        window.hidesOnDeactivate = ProcessInfo.processInfo.environment["BLINK_DEBUG_PIN"] == nil
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.animationBehavior = .utilityWindow
        let controller = NSHostingController(rootView: RelayOverlay(model: model, close: { [weak self] in self?.hideOverlay() }))
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            self?.pinTopEdge()
        }
        return window
    }

    /// Keep the panel's top edge at a fixed height while its content grows or shrinks (Spotlight-style).
    private func pinTopEdge() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let top = vf.maxY - vf.height * topFraction
        panel.setFrameOrigin(NSPoint(x: vf.minX + (vf.width - panel.frame.width) / 2,
                                     y: top - panel.frame.height))
    }

    private func hideOverlay() {
        panel?.onCancel?()
        panel?.orderOut(nil)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else { return event }
            // Let ⌘/⌃/⌥ combinations (copy, paste, quit) reach their normal handlers.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            switch event.keyCode {
            case 125: self.model.moveHighlight(1); return nil      // ↓
            case 126: self.model.moveHighlight(-1); return nil     // ↑
            case 36, 76: self.model.activatePrimary(); return nil  // Return / keypad Enter
            case 48: self.model.swapApps(); return nil             // Tab
            case 53: self.hideOverlay(); return nil                // Esc
            default: return event
            }
        }
    }

    @objc private func quitRelay() { NSApp.terminate(nil) }
}
