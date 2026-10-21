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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = BlinkIdentity.icon(size: 256)
        configureApplicationMenu()
        hotKey.onPress = { [weak self] in
            self?.model.shortcutActivationCount += 1
            self?.showOverlay()
        }
        configureStatusItem()
        let saved = UserDefaults.standard.string(forKey: "relayShortcut")
            .flatMap(HotKeyController.Shortcut.init(rawValue:)) ?? .commandShiftSpace
        if hotKey.register(saved) {
            model.shortcutLabel = saved.label
        } else {
            model.shortcutLabel = "Menu bar"
            model.shortcutNotice = "That shortcut is in use. Open Blink from the menu bar and choose another shortcut."
        }
        model.shortcutDiagnostic = hotKey.diagnostic
        updateShortcutChecks()
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
        item.button?.image = BlinkIdentity.icon(size: 20, template: true)
        let menu = NSMenu()
        let show = NSMenuItem(title: "Open Blink", action: #selector(showOverlay), keyEquivalent: "")
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
        let quit = NSMenuItem(title: "Quit Blink", action: #selector(quitRelay), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func configureApplicationMenu() {
        // Preserve standard text editing shortcuts without creating an empty Settings scene.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Blink")
        let quit = NSMenuItem(title: "Quit Blink", action: #selector(quitRelay), keyEquivalent: "q")
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
                model.shortcutNotice = "The shortcut is unavailable. Open Blink from the menu bar and choose another shortcut."
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
        // Capture foreground context BEFORE Relay becomes active. It suggests an app, never a thread.
        let foreground = NSWorkspace.shared.frontmostApplication
        model.suggestSource(from: foreground)
        model.restoreConnectionIfApproved()
        if panel == nil {
            let availableHeight = (NSScreen.main?.visibleFrame.height ?? 820) - 40
            let window = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: min(680, max(460, availableHeight))),
                                    styleMask: [.titled, .closable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
            window.onCancel = { [weak self] in self?.model.cancelSourceRead(); self?.model.cancelPreparation() }
            model.onDestinationOpened = { [weak window] in window?.orderOut(nil) }
            window.title = "Blink"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.animationBehavior = .utilityWindow
            window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.063, blue: 0.09, alpha: 1)
            window.hasShadow = true
            window.contentView = NSHostingView(rootView: RelayOverlay(model: model, close: { [weak window] in window?.onCancel?(); window?.orderOut(nil) }))
            window.center()
            panel = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitRelay() { NSApp.terminate(nil) }
}
