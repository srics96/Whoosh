import AppKit
import OSLog
import RelayCore
import ServiceManagement
import UserNotifications

@MainActor
final class ContextNudgeMonitor: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "whoosh.context-health"
    private static let tip = "whoosh.context-health.snooze-tip"
    private static let handoff = "whoosh.context-health.handoff"
    private static let snooze = "whoosh.context-health.snooze"
    private static let enabledKey = "whooshContextNudgesEnabled"
    private static let historyKey = "whooshContextNudgeHistory"
    private static let loginPromptKey = "whooshContextLoginPromptShown"
    private let logger = Logger(subsystem: "dev.blinkhandoff.prototype", category: "ContextHealth")
    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private weak var model: RelayModel?
    private var policy: ContextNudgePolicy
    private var loop: Task<Void, Never>?
    private var isChanging = false
    var onOpen: (([ContextNudge], Bool) -> Void)?

    init(model: RelayModel, defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.model = model; self.defaults = defaults; self.center = center
        policy = ContextNudgePolicy(data: defaults.data(forKey: Self.historyKey))
        super.init()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [
            UNNotificationAction(identifier: Self.handoff, title: "Hand off now", options: [.foreground]),
            UNNotificationAction(identifier: Self.snooze, title: "Not now")
        ], intentIdentifiers: [])])
        model.contextNudgesEnabled = defaults.bool(forKey: Self.enabledKey)
        updateOptionsNote()
        model.onNudgesChanged = { [weak self] enabled in self?.setEnabled(enabled) }
        model.onNudgeSelected = { [weak self] in self?.markActed() }
        if model.contextNudgesEnabled { start() }
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        let previous = loop
        previous?.cancel()
        loop = nil
        policy.resetPending()
        return previous
    }

    private func updateOptionsNote() {
        model?.contextNudgeOptionsNote = SMAppService.mainApp.status == .enabled
            ? "Whoosh starts at login." : "Nudges only work while Whoosh is open."
    }

    private func setEnabled(_ enabled: Bool) {
        guard !isChanging, let model else { return }
        guard enabled else {
            if model.contextNudgesEnabled && policy.hasSnoozeTip {
                logger.info("Context nudges turned off after repeated snoozes.")
            }
            defaults.set(false, forKey: Self.enabledKey)
            model.contextNudgesEnabled = false
            model.flaggedNudges = []
            stop()
            clearNotifications()
            return
        }
        guard !model.contextNudgesEnabled else { return }
        isChanging = true
        Task {
            defer { isChanging = false }
            let alert = NSAlert()
            alert.messageText = "Turn on heavy-chat nudges?"
            alert.informativeText = """
            Whoosh checks file sizes and activity for recent chats from connected sources. When a chat is heavy and idle, Whoosh can sample up to 1 MB locally to identify large pastes or tool output. If Codex is connected, Whoosh may check its quota through the approved helper. Chat text stays local and is never included in notifications.
            """
            alert.addButton(withTitle: "Turn On")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let allowed = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard allowed else {
                model.contextNudgeOptionsNote = "Allow Whoosh alerts in System Settings to receive nudges."
                model.errorMessage = "Allow Whoosh notifications in System Settings, then turn on heavy-chat nudges again."
                return
            }
            defaults.set(true, forKey: Self.enabledKey)
            model.contextNudgesEnabled = true
            start()
            promptForLoginOnce()
        }
    }

    private func promptForLoginOnce() {
        guard !defaults.bool(forKey: Self.loginPromptKey) else { return }
        defaults.set(true, forKey: Self.loginPromptKey)
        guard SMAppService.mainApp.status != .enabled else { return }
        let alert = NSAlert()
        alert.messageText = "Start Whoosh at login so nudges keep working?"
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    model?.errorMessage = "Approve Whoosh in System Settings → General → Login Items."
                }
            } catch {
                model?.errorMessage = "Couldn’t start Whoosh at login. Nudges work while Whoosh is open."
            }
        }
        updateOptionsNote()
    }

    private func clearNotifications() {
        Task {
            let notifications = await center.deliveredNotifications()
            guard !defaults.bool(forKey: Self.enabledKey) else { return }
            center.removeDeliveredNotifications(withIdentifiers: notifications.map { $0.request.identifier }
                .filter { $0.hasPrefix("whoosh.context-health.") })
        }
    }

    private func start() {
        guard loop == nil, !defaults.bool(forKey: "blinkDesignPreview") else { return }
        // Separate from the picker so a background timeout cannot cancel a handoff.
        let provider = CodexNativeSourceProvider()
        loop = Task { [weak self] in
            var connected = false
            while !Task.isCancelled {
                guard let self else { break }
                connected = await self.poll(provider: provider, connected: connected)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            await provider.disconnect()
        }
    }

    private func poll(provider: CodexNativeSourceProvider, connected: Bool) async -> Bool {
        guard !Task.isCancelled else { return connected }
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return connected }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              settings.alertSetting != .disabled else {
            if connected { await provider.disconnect() }
            guard !Task.isCancelled else { return false }
            model?.contextNudgeOptionsNote = "Allow Whoosh alerts in System Settings to receive nudges."
            policy.resetPending()
            return false
        }
        updateOptionsNote()
        let now = Date()
        let approvedClaude = defaults.bool(forKey: "blinkClaudeConnectionApproved") && model?.claudeAdapterAvailable == true
        let approvedCodex = defaults.bool(forKey: "blinkCodexConnectionApproved")
        let fixtures = Set((defaults.stringArray(forKey: "blinkOwnedFixtureIDs") ?? []).compactMap(UUID.init(uuidString:)))
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeRoot = home.appendingPathComponent(".claude/projects")
        let codexRoot = home.appendingPathComponent(".codex").appendingPathComponent("sessions")
        var connected = connected
        var rows: [CodexThreadSummary] = []
        if approvedCodex {
            do {
                if !connected, let executable = try await CancellableWork.run({ CodexInstallation.detect() }) {
                    try Task.checkCancellation()
                    _ = try await provider.connect(executableURL: executable, userApproved: true)
                    connected = true
                }
                if connected { rows = try await provider.listThreads().threads }
            } catch {
                await provider.disconnect()
                connected = false
            }
        } else if connected {
            await provider.disconnect()
            connected = false
        }
        guard !Task.isCancelled else { return connected }
        let codexRows = rows
        let logs: [ContextLog] = (try? await CancellableWork.run {
            let claude = approvedClaude ? ((try? ContextLog.claude(root: claudeRoot, now: now)) ?? []) : []
            let codex = codexRows.compactMap { ContextLog.codex($0, root: codexRoot, now: now) }
            return (claude + codex).filter { !fixtures.contains($0.reading.chat.id) }
        }) ?? []
        guard !Task.isCancelled else { return connected }
        let eligible = policy.eligible(logs.map(\.reading), now: now)
        guard !eligible.isEmpty else { return connected }
        var usage: Int?
        if eligible.contains(where: { $0.chat.agent == .codex }),
           let limits = try? await provider.readRateLimits() {
            usage = ContextHealth.codexUsage(limits, now: Date())
        }
        guard !Task.isCancelled else { return connected }
        let byChat = Dictionary(logs.map { ($0.reading.chat, $0) }, uniquingKeysWith: { first, _ in first })
        let codexUsage = usage
        let nudges: [ContextNudge] = (try? await CancellableWork.run {
            var batch: [ContextNudge] = []
            for (index, reading) in eligible.enumerated() {
                try Task.checkCancellation()
                guard let log = byChat[reading.chat] else { continue }
                let agent = reading.chat.agent
                let quotaAdvice = ContextHealth.advice(agent: agent, codexUsage: codexUsage, bloat: nil)
                // Bound total sampling, too. The rest of the group gets the generic advice.
                let details: (bloat: ContextBloat?, project: String?)?
                if index < 4 && (quotaAdvice == .freshSession || log.project == nil) { details = log.inspect() }
                else { details = log.isUnchanged() ? (nil, log.project) : nil }
                guard let details else { continue }
                let fallback = agent == .claude ? "Claude Code project" : "Codex project"
                let project = String((details.project ?? fallback).filter { !$0.isNewline && !$0.isASCIIControl }.prefix(64))
                batch.append(ContextNudge(reading: reading, project: project.isEmpty ? fallback : project,
                    advice: ContextHealth.advice(agent: agent, codexUsage: codexUsage, bloat: details.bloat)))
            }
            return batch
        }) ?? []
        guard !Task.isCancelled else { return connected }
        let stillApproved = nudges.filter { defaults.bool(forKey: $0.chat.agent == .codex
            ? "blinkCodexConnectionApproved" : "blinkClaudeConnectionApproved") }
        if !stillApproved.isEmpty, await notify(stillApproved), !Task.isCancelled {
            policy.delivered(stillApproved, now: Date())
            persist()
        }
        return connected
    }

    private func notify(_ nudges: [ContextNudge]) async -> Bool {
        guard let first = nudges.first, let payload = try? JSONEncoder().encode(nudges) else { return false }
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.category
        if nudges.count == 1 {
            content.title = "Whoosh · Heavy chat"
            content.body = first.advice.message
        } else {
            content.title = "Whoosh · \(nudges.count) chats are heavy"
            content.body = nudges.prefix(3).map(\.project).joined(separator: ", ")
                + (nudges.count > 3 ? ", and \(nudges.count - 3) more." : ".")
        }
        content.userInfo = ["nudges": payload]
        let id = Self.category + "." + UUID().uuidString
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            guard !Task.isCancelled, defaults.bool(forKey: Self.enabledKey) else {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
                return false
            }
            return true
        } catch { return false }
    }

    private func markActed() {
        policy.acted()
        persist()
    }

    private func persist() { defaults.set(policy.data, forKey: Self.historyKey) }

    private func respond(action: String, nudges: [ContextNudge]) async {
        guard defaults.bool(forKey: Self.enabledKey), !nudges.isEmpty else { return }
        switch action {
        case Self.snooze:
            let hadTip = policy.hasSnoozeTip
            policy.snooze(now: Date())
            persist()
            if !hadTip && policy.hasSnoozeTip {
                let content = UNMutableNotificationContent()
                content.title = "Whoosh"
                content.body = "Not finding these useful? You can turn heavy-chat nudges off in Options."
                try? await center.add(UNNotificationRequest(identifier: Self.tip, content: content, trigger: nil))
            }
        case UNNotificationDefaultActionIdentifier, Self.handoff:
            onOpen?(nudges, action == Self.handoff && nudges.count == 1)
        default: break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let data = response.notification.request.content.userInfo["nudges"] as? Data,
              let nudges = try? JSONDecoder().decode([ContextNudge].self, from: data) else { return }
        await respond(action: action, nudges: nudges)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

private extension Character {
    var isASCIIControl: Bool { asciiValue.map { $0 < 32 || $0 == 127 } ?? false }
}
