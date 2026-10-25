import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelayCore

@MainActor
final class RelayModel: ObservableObject {
    enum AgentApp: String, CaseIterable, Identifiable {
        case codex = "Codex", claude = "Claude"
        var id: String { rawValue }
        var displayName: String { self == .claude ? "Claude Code" : "Codex" }
        var other: AgentApp { self == .codex ? .claude : .codex }
        var symbol: String { self == .codex ? "terminal" : "sun.max" }
    }
    enum Stage: Equatable { case compose, preparing, departing, review, opening, complete }
    enum PreparationPhase: String { case snapshot = "Inspecting your selected project", archive = "Preserving context and checking bytes" }
    struct NativeThread: Identifiable {
        let id: String
        let title: String
        let preview: String
        let directory: String?
        var updatedAt: Date? = nil
        var projectName: String { directory.map { URL(fileURLWithPath:$0).lastPathComponent } ?? "Project unavailable" }
    }

    @Published var source: AgentApp = .codex { didSet { if source != oldValue { sourceGeneration = UUID(); invalidate(); clearConversation(); nativeConnected = false; nativeThreads = []; nativeNextCursor = nil; autoConnectionAttempted = false; restoreConnectionIfApproved() } } }
    // Defaults to the same tool: the hotkey's primary job is a fresh session of the agent you're in
    // (context rot), with a cross-tool switch one Tab away.
    @Published var destination: AgentApp = .codex { didSet { if destination != oldValue { invalidate() } } }
    enum DestinationSurface: String, CaseIterable, Identifiable {
        case desktop = "Desktop", terminal = "Terminal (manual)"
        var id: String { rawValue }
    }
    @Published var destinationSurface: DestinationSurface = .desktop { didSet { if destinationSurface != oldValue { invalidate() } } }
    @Published var clipboardNotice: String?
    var sourceProgressTitle: String { selectingThread == nil ? "Finding local conversations…" : "Reading the selected conversation…" }
    /// True when the handoff lands in a fresh session of the same agent, not the other tool.
    var isFreshSession: Bool { source == destination }
    @Published var userInstruction = "" { didSet { if userInstruction != oldValue { invalidate() } } }
    @Published var goal = "" { didSet { if goal != oldValue { invalidate() } } }
    @Published var nextStep = "" { didSet { if nextStep != oldValue { invalidate() } } }
    @Published var decisions = "" { didSet { if decisions != oldValue { invalidate() } } }
    @Published var verification = "" { didSet { if verification != oldValue { invalidate() } } }
    @Published var includeDiff = true { didSet { if includeDiff != oldValue { invalidate() } } }
    @Published var sourceStopped = false { didSet { if !sourceStopped { transferApproved = false } } }
    @Published var transferApproved = false
    @Published var stage: Stage = .compose
    @Published var phase: PreparationPhase = .snapshot
    @Published var conversation: ImportedConversation?
    @Published var conversationNotice: String?
    @Published var projectURL: URL?
    @Published var outputURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Whoosh/Handoffs", isDirectory: true)
    @Published var prepared: PreparedHandoff?
    @Published var errorMessage: String?
    @Published var foregroundHint = "Choose a source app and a conversation."
    @Published var shortcutLabel = "⌘ ⇧ Space"
    @Published var shortcutNotice: String?
    @Published var importBusy = false
    @Published var nativeBusy = false
    @Published var nativeConnected = false
    @Published var nativeThreads: [NativeThread] = []
    @Published var nativeNextCursor: String?
    @Published var nativeSelectedID: String?
    @Published var nativeNotice: String?
    @Published var nativeExpanded = true
    @Published var nativeSearch = ""
    @Published var shortcutActivationCount = 0
    @Published var shortcutDiagnostic = "Not registered"
    @Published var reduceMotionInWhoosh = false
    @Published var rememberedCLIPath: String?
    @Published var nativeStatusNotice: String?
    @Published var sensitiveContentBlocked = false
    @Published var sourceIdleKnown = false

    @Published var includeOwnedTestChats = false
    @Published var selectingThread: NativeThread?
    @Published var highlightedID: String?
    /// True only when the highlight last moved via the keyboard. The list auto-scrolls to follow
    /// keyboard navigation, but NOT hover — otherwise scrolling with the trackpad passes the cursor
    /// over rows, moves the highlight, and recenters the list, fighting your scroll.
    var highlightByKeyboard = false
    var visibleNativeThreads: [NativeThread] {
        let query = nativeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixtures = Set(UserDefaults.standard.stringArray(forKey: "blinkOwnedFixtureIDs") ?? [])
        // Most-recently-active first: the chat you were just in is the newest, so it lands on top
        // and gets the default highlight — Whoosh "lands" on where you are without reading the window.
        let rows = nativeThreads
            .filter { includeOwnedTestChats || !fixtures.contains($0.id) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        return query.isEmpty ? rows : rows.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.projectName.localizedCaseInsensitiveContains(query) }
    }
    @Published var nativeRateSummary: [String] = []
    @Published var nativeRateCheckedAt: Date?
    @Published var completionTitle = "Handoff prepared"
    @Published var completionDetail = ""
    @Published var codexApplicationURL: URL?
    @Published var claudeLinkAvailable = false
    @Published var claudeApplicationURL: URL?
    var onDestinationOpened: (() -> Void)?
    private var sourceGeneration = UUID()
    private var handoffTask: Task<Void, Never>?
    private var autoFly = false
    private var resumeBrief = ""
    private var hasExplicitSource = false
    private var autoConnectionAttempted = false
    private var nativeProvider: CodexNativeSourceProvider
    private var selectedNativeResult: CodexSelectedThread?
    private var nativeSelectionTask: Task<Void, Never>?
    var canCancelSourceRead: Bool { nativeSelectionTask != nil && (nativeBusy || importBusy) }
    private let claudeAdapter: ClaudeSessionAdapter
    private var selectedClaudeInfo: ClaudeSessionInfo?
    var claudeAdapterAvailable: Bool { claudeAdapter.available }

    init(nativeProvider: CodexNativeSourceProvider = CodexNativeSourceProvider(),
         claudeAdapter: ClaudeSessionAdapter = ClaudeSessionAdapter()) {
        self.nativeProvider = nativeProvider
        self.claudeAdapter = claudeAdapter
    }

    var isBusy: Bool { stage == .preparing || stage == .departing || stage == .opening || nativeBusy || importBusy }
    var canPrepare: Bool {
        conversation != nil && !sensitiveContentBlocked && projectURL != nil && outputURL != nil &&
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }
    var byteLabel: String {
        guard let conversation else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(conversation.byteCount), countStyle: .file)
    }
    var sourceIsNative: Bool { selectedNativeResult != nil || selectedClaudeInfo != nil }
    var conversationDisplayName: String? {
        if let id = nativeSelectedID, let thread = nativeThreads.first(where: { $0.id == id }) { return thread.title }
        return conversation?.fileName
    }
    var transferDescription: String {
        destination == .claude
            ? "Open a new Claude draft with this bootstrap and local archive references. Claude may ask you to confirm the project folder. Reading the files may require access approval. Nothing is submitted by Whoosh."
            : "Open a new Codex draft with this bootstrap and local archive references. Codex receives the draft text; reading the files may require access approval. Nothing is submitted. Verify the draft before sending."
    }

    func suggestSource(from app: NSRunningApplication?) {
        guard !isBusy, !hasExplicitSource, conversation == nil, stage == .compose,
              let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let name = (app.localizedName ?? "").lowercased()
        let identifier = (app.bundleIdentifier ?? "").lowercased()
        if name.contains("claude") || identifier.contains("claude") {
            source = .claude; destination = .claude
            foregroundHint = "Claude Code was in front. Pick a chat for a fresh session."
        } else if name.contains("codex") || identifier.contains("codex") {
            source = .codex; destination = .codex
            foregroundHint = "Codex was in front. Pick a chat for a fresh session."
        } else {
            foregroundHint = "Choose a source app. Whoosh does not inspect your active chat."
        }
    }

    func chooseSource(_ app: AgentApp) {
        guard !isBusy else { return }
        hasExplicitSource = true
        source = app
        // Switching which agent you read defaults back to a fresh session of that same agent.
        destination = app
        foregroundHint = "Reading \(app.displayName) chats. Pick one for a fresh session."
    }

    /// Tab / the direction pill: toggle the destination between a fresh same-agent session and the other tool.
    func swapApps() {
        guard !isBusy else { return }
        destination = isFreshSession ? source.other : source
    }

    /// The options menu: read the other agent's chats instead (source switch, not destination toggle).
    func readOtherSource() { chooseSource(source.other) }

    // MARK: Keyboard-first selection

    /// Keep a valid highlight as the visible rows change. On a fresh open with no query we
    /// select NOTHING: Whoosh shows the best ordering and lets you choose, rather than
    /// pre-committing to a chat it can't be sure is the one you're in. The top match is
    /// auto-highlighted only once you've typed to narrow the list (standard launcher behavior).
    func ensureHighlight() {
        let rows = visibleNativeThreads
        if let id = highlightedID, rows.contains(where: { $0.id == id }) { return }
        let hasQuery = !nativeSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        highlightedID = hasQuery ? rows.first?.id : nil
    }

    func moveHighlight(_ delta: Int) {
        let rows = visibleNativeThreads
        guard !rows.isEmpty else { return }
        highlightByKeyboard = true
        // First arrow press from a clean open selects the top row; thereafter it moves.
        guard let id = highlightedID, let current = rows.firstIndex(where: { $0.id == id }) else {
            highlightedID = rows.first?.id
            return
        }
        highlightedID = rows[max(0, min(rows.count - 1, current + delta))].id
    }

    /// Context-aware Return: reset after a finished handoff, connect if needed, else fly the highlighted chat.
    func activatePrimary() {
        guard !isBusy else { return }
        if stage == .complete || stage == .review { startAgain(); return }
        if !nativeConnected { reconnectNativeCodex(); return }
        flyHighlighted()
    }

    /// Select the highlighted conversation and, as soon as it is read, send it onward — the whoosh.
    func flyHighlighted() {
        guard nativeConnected, !isBusy else { return }
        ensureHighlight()
        guard let id = highlightedID else { return }
        autoFly = true
        selectNativeThread(id)
    }

    func invalidate() {
        guard stage != .preparing && stage != .departing && stage != .opening else { return }
        prepared = nil
        transferApproved = false
        clipboardNotice = nil
        sourceStopped = sourceIdleKnown
        stage = .compose
        errorMessage = nil
    }

    func clearConversation() {
        sourceIdleKnown = false
        sourceStopped = false
        sourceIdleKnown = false
        conversation = nil
        selectingThread = nil
        conversationNotice = nil
        selectedNativeResult = nil
        selectedClaudeInfo = nil
        nativeSelectedID = nil
        userInstruction = ""
        nativeStatusNotice = nil
        sensitiveContentBlocked = false
        projectURL = nil
        goal = ""
        nextStep = ""
        decisions = ""
        verification = ""
        resumeBrief = ""
    }

    func importConversation() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose one exported conversation"
        panel.message = "Whoosh reads only this file. Its original bytes are preserved in the handoff archive."
        panel.allowedContentTypes = [.plainText, .json, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        invalidate()
        importBusy = true
        nativeSelectionTask = Task {
            defer { importBusy = false; nativeSelectionTask = nil }
            do {
                let (value, blocked) = try await CancellableWork.run {
                    let value = try ImportedConversation.readSelectedFile(url)
                    return (value, try SensitiveContentScreen.scan(value.data))
                }
                clearConversation()
                conversation = value
                setAutomaticCheckpoint(title: value.fileName)
                sensitiveContentBlocked = blocked
                conversationNotice = "Exact selected-file bytes. This preserves your export, not a native conversation ID or hidden tool state."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func chooseFolder(output: Bool) {
        let panel = NSOpenPanel()
        panel.title = output ? "Choose where to save this handoff" : "Choose your project folder"
        panel.message = output ? "Choose a private, non-synced folder. Whoosh creates a new handoff folder here; existing sharing, cloud sync or Git can disclose its contents." : "Whoosh reads Git metadata here. It never changes project files."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = output
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        invalidate()
        if output {
            outputURL = url
            UserDefaults.standard.set(url.path, forKey: "blinkChosenOutput")
        } else { projectURL = url }
    }

    func continueHandoff() { prepare(continueToDestination: true) }

    func prepare(continueToDestination: Bool = false) {
        guard canPrepare, let conversation, let projectURL, let outputURL else { return }
        let checkpoint = Checkpoint(sourceName: source.rawValue, goal: goal, decisions: decisions,
                                    nextStep: userInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nextStep : userInstruction, verification: verification, sourceSessionStopped: true)
        let instructionData = Data((goal + nextStep + userInstruction + decisions + verification).utf8)
        let captureDiff = includeDiff
        let brief = resumeBrief
        errorMessage = nil
        transferApproved = false
        stage = .preparing
        phase = .snapshot
        handoffTask = Task {
            do {
                // Reuse the selected capture; check archive integrity before opening a destination.
                let snapshot = try await CancellableWork.run {
                    guard try !SensitiveContentScreen.scan(instructionData) else {
                        throw RelayError.invalidInput("Possible sensitive data in your instructions. Remove it before continuing.")
                    }
                    try PrivateHandoffStorage.ensureDirectory(outputURL)
                    try ProjectFolder.require(projectURL)
                    return try GitSnapshotReader.captureCheckingCancellation(projectURL: projectURL, includeDiff: captureDiff)
                }
                phase = .archive
                let result = try await CancellableWork.run {
                    try HandoffWriter.prepare(conversation: conversation, checkpoint: checkpoint,
                                              projectURL: projectURL, outputParent: outputURL, gitSnapshot: snapshot, brief: brief)
                }
                try Task.checkCancellation()
                prepared = result
                refreshDestinationCapabilities()
                stage = .review
                if continueToDestination {
                    try Task.checkCancellation()
                    transferApproved = true
                    if destinationSurface == .desktop {
                        if destination == .codex { launchCodex() } else { launchClaude() }
                    }
                }
            } catch is CancellationError {
                stage = .compose
                transferApproved = false
                errorMessage = "Handoff cancelled. Your conversation is still selected."
            } catch {
                errorMessage = error.localizedDescription
                stage = .compose
                transferApproved = false
            }
        }
    }

    func cancelPreparation() {
        guard stage == .preparing || stage == .departing else { return }
        handoffTask?.cancel()
    }

    var selectionBlocker: String? {
        if nativeBusy { return sourceProgressTitle }
        if conversation == nil { return "Choose a conversation first." }
        if sensitiveContentBlocked { return "Possible sensitive data found. Review the history before continuing." }
        if projectURL == nil { return "This conversation has no available project folder. Choose it once below." }
        if outputURL == nil { return "Private handoff storage is unavailable. Re-select the conversation to retry." }
        if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Conversation context is incomplete. Re-select it to rebuild the draft." }
        if !sourceStopped { return "Confirm the source has stopped before continuing." }
        return nil
    }

    func refreshDestinationCapabilities() {
        if let prepared {
            claudeApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: prepared.deepLink)
            claudeLinkAvailable = claudeApplicationURL.map { Bundle(url: $0)?.bundleIdentifier == "com.anthropic.claudefordesktop" } ?? false
        }
        codexApplicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        if let app = codexApplicationURL, Bundle(url: app)?.bundleIdentifier != "com.openai.codex" {
            codexApplicationURL = nil
        }
    }

    func editCheckpoint() {
        // A changed checkpoint always requires a fresh package and new review.
        invalidate()
    }

    private func validateDestinationProject() -> Bool {
        guard let prepared else { return false }
        do { try ProjectFolder.require(URL(fileURLWithPath: prepared.manifest.projectPath)); return true }
        catch { transferApproved = false; errorMessage = error.localizedDescription; return false }
    }

    func launchClaude() {
        guard validateDestinationProject() else { return }
        guard destination == .claude, stage == .review, transferApproved, sourceStopped,
              let prepared else { return }
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: prepared.deepLink) else {
            errorMessage = "No app is registered for the Claude Code link. Install or update Claude, or reveal the files and continue manually."
            return
        }
        guard Bundle(url: handler)?.bundleIdentifier == "com.anthropic.claudefordesktop" else {
            claudeApplicationURL = handler
            claudeLinkAvailable = false
            transferApproved = false
            errorMessage = "The Claude link handler is not the expected official Claude app. Nothing was passed to it. Use the handoff files manually instead."
            return
        }
        guard handler == claudeApplicationURL else {
            claudeApplicationURL = handler
            transferApproved = false
            errorMessage = "The app registered for Claude links changed. Review its location and approve again before opening."
            return
        }
        stage = .opening
        errorMessage = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([prepared.deepLink], withApplicationAt: handler, configuration: configuration) { [weak self] app, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.stage = .review
                } else if app != nil {
                    self.completionTitle = "Draft requested in Claude"
                    self.completionDetail = "Check Claude’s new composer for the bootstrap. Whoosh cannot confirm that Claude displayed or read it. Nothing was submitted by Whoosh. Review before sending."
                    self.stage = .complete
                    self.onDestinationOpened?()
                } else {
                    self.errorMessage = "macOS did not confirm that Claude opened. Your handoff files are still ready."
                    self.stage = .review
                }
            }
        }
    }

    func chooseCodexApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex application"
        panel.message = "Whoosh will only open this app after your review. It cannot load a conversation into Codex."
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Bundle(url: url)?.bundleIdentifier == "com.openai.codex" else {
            transferApproved = false
            errorMessage = "That app does not have the expected official Codex bundle identifier. Choose Codex, or use the handoff files manually."
            return
        }
        codexApplicationURL = url
        transferApproved = false
    }

    func launchCodex() {
        guard validateDestinationProject() else { return }
        guard destination == .codex, stage == .review, transferApproved, sourceStopped,
              let prepared else { return }
        guard let appURL = codexApplicationURL else {
            transferApproved = false
            errorMessage = "Codex is unavailable. Your archive is preserved; install or locate the official app before opening a draft."
            return
        }
        do {
            let link = try CodexLink.make(prompt: prepared.bootstrap, projectPath: prepared.manifest.projectPath)
            guard let handler = NSWorkspace.shared.urlForApplication(toOpen: link),
                  handler == appURL, Bundle(url: handler)?.bundleIdentifier == "com.openai.codex" else {
                transferApproved = false
                throw RelayError.invalidInput("The Codex link handler is missing or changed. Use local files manually.")
            }
            stage = .opening
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([link], withApplicationAt: handler, configuration: configuration) { [weak self] app, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.stage = .review
                    } else if app != nil {
                        self.completionTitle = "Draft requested in Codex"
                        self.completionDetail = "Check the new composer for the bootstrap. Whoosh cannot confirm that Codex displayed or read it. Nothing was submitted by Whoosh. Review before sending."
                        self.stage = .complete
                    self.onDestinationOpened?()
                    } else {
                        self.errorMessage = "macOS did not confirm the draft request. Use the preserved files manually."
                        self.stage = .review
                    }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func copyTerminalCommand() {
        guard destinationSurface == .terminal, stage == .review, let prepared else { return }
        do {
            let command = try TerminalHandoff.launchCommand(agent: destination == .claude ? .claude : .codex,
                projectURL: URL(fileURLWithPath: prepared.manifest.projectPath))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            clipboardNotice = "Launch command copied. Run it in your terminal; it contains no prompt."
        } catch { errorMessage = error.localizedDescription }
    }

    func copyReviewedBootstrap() {
        guard stage == .review, let prepared else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prepared.bootstrap, forType: .string)
        clipboardNotice = "Bootstrap copied. Paste into the new session, review, then send when ready."
    }

    func revealFiles() {
        guard let prepared else { return }
        NSWorkspace.shared.activateFileViewerSelecting([prepared.directory])
    }

    func finishManually() {
        guard stage == .review, sourceStopped, prepared != nil else { return }
        revealFiles()
        completionTitle = "Your handoff is ready"
        completionDetail = "No app was opened and nothing was sent. Open bootstrap.txt from the handoff folder and provide it to a new conversation when you’re ready."
        stage = .complete
    }

    func startAgain() {
        hasExplicitSource = false
        invalidate()
        clearConversation()
        goal = ""; nextStep = ""; decisions = ""; verification = ""
    }

    var canRefreshConversations: Bool {
        nativeConnected && !isBusy && stage == .compose && conversation == nil
    }

    /// Reopening the picker refreshes metadata, never a selected history or prepared draft.
    func refreshForPresentation() {
        if nativeConnected { refreshConversations() }
        else { restoreConnectionIfApproved() }
    }

    func refreshConversations() {
        guard canRefreshConversations else { return }
        let requestedSource = source
        let generation = sourceGeneration
        selectingThread = nil
        nativeBusy = true
        errorMessage = nil
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do {
                var rows: [NativeThread]
                let cursor: String?
                if requestedSource == .codex {
                    // Reuse the existing connection; do not restart/schema-parse the helper.
                    let page = try await nativeProvider.listThreads()
                    rows = page.threads.map { NativeThread(id: $0.id, title: $0.displayName,
                        preview: $0.preview ?? "", directory: $0.cwd,
                        updatedAt: $0.updatedAt.map(Date.init(timeIntervalSince1970:))) }
                    cursor = page.nextCursor
                } else {
                    let page = try await claudeAdapter.call(action: "list", offset: 0)
                    rows = (page.sessions ?? []).map { NativeThread(id: $0.sessionId, title: $0.summary,
                        preview: "", directory: $0.cwd, updatedAt: Date(timeIntervalSince1970: $0.lastModified / 1000)) }
                    cursor = page.nextOffset.map(String.init)
                }
                try Task.checkCancellation()
                guard source == requestedSource, sourceGeneration == generation else { return }
                var seen = Set<String>()
                rows = rows.filter { seen.insert($0.id).inserted }
                nativeThreads = rows
                nativeNextCursor = cursor
                ensureHighlight()
            } catch {
                guard source == requestedSource, sourceGeneration == generation else { return }
                // Keep the cached rows/query intact; errors must never look like an empty account.
                errorMessage = error is CancellationError
                    ? "Conversation refresh cancelled. Reopen to try again."
                    : "Couldn’t refresh conversations. Cached results are shown. " + error.localizedDescription
                if error is CancellationError && requestedSource == .codex {
                    nativeConnected = false
                    autoConnectionAttempted = false
                }
            }
        }
    }

    func restoreConnectionIfApproved() {
        guard !UserDefaults.standard.bool(forKey:"blinkDesignPreview") else { return }
        guard !nativeConnected, !isBusy, !autoConnectionAttempted,
              UserDefaults.standard.bool(forKey: source == .codex ? "blinkCodexConnectionApproved" : "blinkClaudeConnectionApproved") else { return }
        autoConnectionAttempted = true
        reconnectNativeCodex()
    }

    func connectNativeCodex() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Select your installed Codex CLI"
        panel.message = "Whoosh starts your selected Codex CLI with its own ordinary configuration and account, and reads the local histories it exposes. Whoosh does not inspect credential files or start an agent turn, but CLI launch can have normal internal side effects. Choose only an official Codex executable you trust."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Connect read-only"
        guard panel.runModal() == .OK, let executable = panel.url else { return }
        connectNativeCodex(executable: executable)
    }

    func reconnectNativeCodex() {
        guard !isBusy else { return }
        if source == .claude { connectClaude(); return }
        nativeConnected = false
        selectingThread = nil
        nativeBusy = true
        errorMessage = nil
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do {
                guard let executable = try await CancellableWork.run({ CodexInstallation.detect() }) else {
                    rememberedCLIPath = nil
                    throw RelayError.invalidInput("Couldn’t find Codex. Install the Codex app (or CLI), or choose Options → Locate Codex helper.")
                }
                try await readCodexConnection(executable: executable)
            } catch { errorMessage = error is CancellationError ? "Connection cancelled. Reopen to try again." : error.localizedDescription; autoConnectionAttempted = false }
        }
    }

    private func connectNativeCodex(executable: URL) {
        nativeConnected = false
        selectingThread = nil
        nativeBusy = true
        errorMessage = nil
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do {
                guard let verified = try await CancellableWork.run({ CodexInstallation.verified(executable) }) else {
                    throw RelayError.invalidInput("This executable could not be verified as signed by OpenAI. No program was run.")
                }
                try await readCodexConnection(executable: verified)
            }
            catch { errorMessage = error is CancellationError ? "Connection cancelled." : error.localizedDescription; autoConnectionAttempted = false }
        }
    }

    private func readCodexConnection(executable: URL) async throws {
        _ = try await nativeProvider.connect(executableURL: executable, userApproved: true)
        try Task.checkCancellation()
        rememberedCLIPath = executable.path
        UserDefaults.standard.set(executable.path, forKey: "blinkChosenCLI")
        UserDefaults.standard.set(true, forKey: "blinkCodexConnectionApproved")
        let page = try await nativeProvider.listThreads()
        try Task.checkCancellation()
        applyNativePage(page, append: false)
        nativeConnected = true
        nativeNotice = "Connected to your chosen local Codex CLI. This is not your desktop app’s selected conversation."
    }

    func loadMoreNativeThreads() {
        if source == .claude { connectClaude(offset: Int(nativeNextCursor ?? "0") ?? 0); return }
        guard nativeConnected, !nativeBusy, let cursor = nativeNextCursor else { return }
        selectingThread = nil
        nativeBusy = true
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do { applyNativePage(try await nativeProvider.listThreads(cursor: cursor), append: true) }
            catch { if error is CancellationError { nativeConnected = false; autoConnectionAttempted = false }; errorMessage = error.localizedDescription }
        }
    }

    private func applyNativePage(_ page: CodexThreadPage, append: Bool) {
        let rows = page.threads.map { item in
            NativeThread(id: item.id, title: item.displayName,
                         preview: item.preview ?? "", directory: item.cwd, updatedAt: item.updatedAt.map(Date.init(timeIntervalSince1970:)))
        }
        if append { nativeThreads += rows.filter { row in !nativeThreads.contains { $0.id == row.id } } }
        else { nativeThreads = rows }
        nativeNextCursor = page.nextCursor
    }

    func selectNativeThread(_ id: String) {
        if source == .claude { selectClaude(id); return }
        guard nativeConnected, !nativeBusy else { return }
        invalidate()
        clearConversation()
        nativeBusy = true
        selectingThread = nativeThreads.first { $0.id == id }
        nativeSelectionTask = Task {
            var ok = false
            do {
                let result = try await nativeProvider.readThread(id: id)
                try Task.checkCancellation()
                let (archive, digest, blocked) = try await CancellableWork.run {
                    let archive = try ImportedConversation(fileName: "codex-selected-responses.jsonl", data: result.rawResponsesJSONL,
                                                           preservationNotice: result.preservationNotice, isPartial: result.isPartial)
                    let digest = ResumeDigest(title: result.summary.displayName,
                        messages: result.messages.map { ResumeMessage(role: $0.role.rawValue, text: $0.text) })
                    return (archive, digest, try SensitiveContentScreen.scan(archive.data))
                }
                clearConversation()
                selectingThread = nativeThreads.first { $0.id == id }
                selectedNativeResult = result
                nativeSelectedID = id
                conversation = archive
                projectURL = ProjectFolder.available(result.summary.cwd)
                setAutomaticCheckpoint(digest)
                sensitiveContentBlocked = blocked
                sourceIdleKnown = result.summary.status?.type == "idle"
                sourceStopped = true
                conversationNotice = result.preservationNotice + (result.isPartial ? " This result is partial. Export your full conversation if you need complete context." : "")
                ok = true
            } catch CodexSourceError.responseTooLarge {
                nativeConnected = false
                errorMessage = "Full history exceeds the 240 MiB capture budget. No continuation was prepared. Use a complete explicit export or reduce source attachments."
            } catch is CancellationError {
                nativeConnected = false
                autoConnectionAttempted = false
                errorMessage = "History capture cancelled. Reopen to choose a chat."
            } catch {
                nativeConnected = false
                errorMessage = error.localizedDescription
            }
            nativeBusy = false
            nativeSelectionTask = nil
            let fly = autoFly; autoFly = false
            if ok && sensitiveContentBlocked {
                errorMessage = "Possible sensitive data found. Review and redact the history before continuing."
            } else if ok && projectURL == nil {
                errorMessage = "This conversation’s project folder is missing. Choose a folder explicitly; no home-directory fallback was used."
            } else if ok && fly { continueHandoff() }
        }
    }

    func cancelSourceRead() {
        autoFly = false
        nativeSelectionTask?.cancel()
    }

    private func connectClaude(offset: Int = 0) {
        guard !nativeBusy else { return }
        selectingThread = nil
        nativeBusy = true; errorMessage = nil
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do {
                let result = try await claudeAdapter.call(action: "list", offset: offset)
                try Task.checkCancellation()
                let rows = (result.sessions ?? []).map { NativeThread(id:$0.sessionId, title:$0.summary, preview:"", directory:$0.cwd, updatedAt:Date(timeIntervalSince1970:$0.lastModified / 1000)) }
                if offset == 0 { nativeThreads = rows } else { nativeThreads += rows.filter { row in !nativeThreads.contains { $0.id == row.id } } }
                nativeNextCursor = result.nextOffset.map(String.init)
                nativeConnected = true
                UserDefaults.standard.set(true, forKey: "blinkClaudeConnectionApproved")
                nativeNotice = "Local Claude Code histories only. Chat/Cowork and desktop-origin coverage are not established."
            } catch { errorMessage = error is CancellationError ? "Connection cancelled." : error.localizedDescription; autoConnectionAttempted = false }
        }
    }

    private func selectClaude(_ id: String) {
        guard nativeConnected, !nativeBusy, let row = nativeThreads.first(where: { $0.id == id }) else { return }
        invalidate(); clearConversation(); selectingThread = row; nativeBusy = true
        nativeSelectionTask = Task {
            var ok = false
            do {
                let result = try await claudeAdapter.call(action: "read", id: id, dir: row.directory)
                guard let info = result.info, let text = result.archive, let notice = result.notice else {
                    throw RelayError.invalidInput("No readable Claude Code history returned.")
                }
                let (archive, digest, blocked) = try await CancellableWork.run {
                    let archive = try ImportedConversation(fileName:"claude-code-api.jsonl", data:Data(text.utf8), preservationNotice:notice, isPartial:true)
                    let digest = ResumeDigest(title: info.summary,
                        messages: (result.digest ?? []).map { ResumeMessage(role: $0.role, text: $0.text) })
                    return (archive, digest, try SensitiveContentScreen.scan(archive.data))
                }
                clearConversation(); selectingThread = row; selectedClaudeInfo = info; nativeSelectedID = id; conversation = archive
                projectURL = ProjectFolder.available(info.cwd)
                setAutomaticCheckpoint(digest)
                sensitiveContentBlocked = blocked
                sourceIdleKnown = false; sourceStopped = true
                conversationNotice = notice
                ok = true
            } catch { errorMessage = error is CancellationError ? "History capture cancelled." : error.localizedDescription }
            nativeBusy = false
            nativeSelectionTask = nil
            let fly = autoFly; autoFly = false
            if ok && sensitiveContentBlocked {
                errorMessage = "Possible sensitive data found. Review and redact the history before continuing."
            } else if ok && projectURL == nil {
                errorMessage = "This conversation’s project folder is missing. Choose a folder explicitly; no home-directory fallback was used."
            } else if ok && fly { continueHandoff() }
        }
    }

    private func setAutomaticCheckpoint(title: String) {
        setAutomaticCheckpoint(ResumeDigest(title: title, messages: []))
    }

    private func setAutomaticCheckpoint(_ digest: ResumeDigest) {
        goal = digest.goal
        nextStep = digest.nextStep
        decisions = "See the transcript and BRIEF.md for recorded decisions; ask rather than invent."
        verification = "History is a transcript snapshot, not independent verification of current project state. Inspect the working tree before changing it."
        resumeBrief = digest.brief
    }

    func readNativeUsage() {
        guard nativeConnected, !nativeBusy else { return }
        nativeBusy = true
        nativeSelectionTask = Task {
            defer { nativeBusy = false; nativeSelectionTask = nil }
            do {
                let snapshot = try await nativeProvider.readRateLimits()
                try Task.checkCancellation()
                nativeRateCheckedAt = snapshot.capturedAt
                nativeRateSummary = snapshot.buckets.flatMap { bucket -> [String] in
                    let title = bucket.limitName ?? bucket.limitId ?? "Codex"
                    return [("Primary", bucket.primary), ("Secondary", bucket.secondary)].compactMap { pair in
                        guard let window = pair.1 else { return nil }
                        let used = window.usedPercent.map { String(format: "%.0f%% used", $0) } ?? "usage unknown"
                        let reset = window.resetsAt.map { " · resets " + Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened) } ?? ""
                        return "\(title) · \(pair.0): \(used)\(reset)"
                    }
                }
                if nativeRateSummary.isEmpty { nativeRateSummary = ["This account did not return usage windows."] }
            } catch { if error is CancellationError { nativeConnected = false; autoConnectionAttempted = false }; errorMessage = error.localizedDescription }
        }
    }

    func shutdown() async {
        let selection = nativeSelectionTask
        let handoff = handoffTask
        cancelSourceRead()
        handoff?.cancel()
        await nativeProvider.disconnect()
        await selection?.value
        await handoff?.value
    }

    func disconnectNativeCodex() {
        sourceGeneration = UUID()
        UserDefaults.standard.set(false, forKey: source == .codex ? "blinkCodexConnectionApproved" : "blinkClaudeConnectionApproved")
        autoConnectionAttempted = true
        nativeConnected = false
        nativeThreads = []
        nativeNextCursor = nil
        nativeNotice = nil
        nativeRateSummary = []
        nativeRateCheckedAt = nil
        if sourceIsNative { invalidate(); clearConversation() }
        Task { await nativeProvider.disconnect() }
    }
}
