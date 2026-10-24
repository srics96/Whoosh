import SwiftUI
import AppKit
import RelayCore

/// Spotlight-style handoff surface: one screen, keyboard-first, built to feel instant.
/// Open with the hotkey, type to filter, press Return to send the chat to the other app.
@MainActor
struct RelayOverlay: View {
    @ObservedObject var model: RelayModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var showOptions = false
    @FocusState private var searchFocused: Bool

    private var reduced: Bool { systemReduceMotion || model.reduceMotionInWhoosh }
    private var rows: [RelayModel.NativeThread] { model.visibleNativeThreads }
    private var flying: Bool { model.isBusy || model.stage == .complete || model.stage == .review }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                if flying {
                    flight
                        .transition(.opacity)
                } else {
                    searchBar
                    Divider().overlay(Color.white.opacity(0.08))
                    content
                }
                hintBar
            }
        }
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(.white)
        .tint(WhooshGeometry.accent)
        .animation(reduced ? nil : .easeInOut(duration: 0.22), value: flying)
        .onAppear { searchFocused = true; model.ensureHighlight() }
        .onChange(of: model.source) { _ in searchFocused = true }
        .onChange(of: model.nativeSearch) { _ in model.ensureHighlight() }
        .onChange(of: model.nativeThreads.count) { _ in model.ensureHighlight() }
    }

    // MARK: Chrome

    private var background: some View {
        // A solid near-opaque fill instead of `.ultraThinMaterial`: the gradient above it already sat
        // at ~0.9 alpha, so the live backdrop blur was barely visible yet re-composited the whole
        // desktop behind this floating panel every frame. Dropping it removes that standing GPU cost.
        LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.13),
                                Color(red: 0.035, green: 0.035, blue: 0.065)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var header: some View {
        HStack(spacing: 12) {
            WhooshMark(active: flying).frame(width: 22, height: 20)
            directionPill
            Spacer()
            Menu {
                Button(model.isFreshSession ? "Send to \(model.source.other.displayName) instead" : "Keep it in \(model.source.displayName) (fresh session)") { model.swapApps() }.disabled(flying)
                Button("Read \(model.source.other.displayName) chats instead") { model.readOtherSource() }.disabled(flying)
                if model.nativeConnected { Button("Disconnect " + model.source.displayName) { model.disconnectNativeCodex() }.disabled(flying) }
                Divider()
                Button("Import a conversation export…") { model.importConversation() }
                Button("Locate Codex helper…") { model.connectNativeCodex() }
                Toggle("Reduce motion", isOn: $model.reduceMotionInWhoosh)
                Toggle("Include Whoosh test chats", isOn: $model.includeOwnedTestChats)
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Options")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var directionPill: some View {
        Button { model.swapApps() } label: {
            HStack(spacing: 8) {
                providerIcon(model.source, 18)
                Text(model.source.displayName).font(.system(size: 13, weight: .semibold))
                if model.isFreshSession {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    Text("fresh session").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    providerIcon(model.destination, 18)
                    Text(model.destination.displayName).font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(flying)
        .help(model.isFreshSession ? "Fresh \(model.source.displayName) session — ⇥ to switch tools" : "⇥ to keep it in \(model.source.displayName)")
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            TextField("", text: $model.nativeSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .focused($searchFocused)
                .disabled(!model.nativeConnected)
                .overlay(alignment: .leading) {
                    if model.nativeSearch.isEmpty {
                        Text(model.nativeConnected ? "Search your \(model.source.displayName) chats…" : "Connect to search")
                            .font(.system(size: 21)).foregroundStyle(.white.opacity(0.32)).allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    // MARK: Content states

    @ViewBuilder private var content: some View {
        if let error = model.errorMessage {
            banner(error)
        }
        if !model.nativeConnected {
            connectState
        } else if rows.isEmpty {
            emptyState
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(rows) { row in
                        ConversationRow(row: row,
                                        highlighted: row.id == model.highlightedID,
                                        destination: model.destination.displayName)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.highlightByKeyboard = false; model.highlightedID = row.id; model.flyHighlighted() }
                            .onHover { if $0 { model.highlightByKeyboard = false; model.highlightedID = row.id } }
                    }
                    if model.nativeNextCursor != nil {
                        Button(action: model.loadMoreNativeThreads) {
                            Text(model.nativeBusy ? "Loading…" : "Show more")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.plain).disabled(model.nativeBusy)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(maxHeight: 360)
            .onChange(of: model.highlightedID) { id in
                // Only follow keyboard navigation — never hover — so the trackpad scrolls freely.
                guard let id, model.highlightByKeyboard else { return }
                model.highlightByKeyboard = false
                withAnimation(reduced ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id) }
            }
        }
    }

    private var connectState: some View {
        VStack(spacing: 16) {
            providerIcon(model.source, 46).opacity(0.9)
            Text("Connect to your \(model.source.displayName) chats")
                .font(.system(size: 18, weight: .semibold))
            Text(model.source == .claude
                 ? "Reads your local Claude Code sessions, read-only. Chat and Cowork aren’t available here."
                 : "Starts your signature-verified Codex CLI once, read-only, to list your recent chats.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            Button { model.reconnectNativeCodex() } label: {
                Text(model.nativeBusy ? "Connecting…" : "Connect \(model.source.displayName)  ↵")
            }
            .buttonStyle(RelayPrimaryButton()).frame(width: 260).disabled(model.nativeBusy)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 46).padding(.horizontal, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30)).foregroundStyle(.white.opacity(0.3))
            Text(model.nativeSearch.isEmpty ? "No conversations here yet." : "Nothing matches “\(model.nativeSearch)”.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Flight (the whoosh)

    private var flight: some View {
        VStack(spacing: 22) {
            ZStack {
                WhooshTrail(active: model.stage != .complete && model.stage != .review, forceReduceMotion: reduced)
                    .frame(height: 96)
                HStack {
                    providerIcon(model.source, 42)
                        .scaleEffect(departed ? 0.6 : 1).opacity(departed ? 0.25 : 1)
                    Spacer()
                    providerIcon(model.destination, 52)
                        .scaleEffect(model.stage == .complete ? 1.12 : (departed ? 1.04 : 0.92))
                        .shadow(color: WhooshGeometry.blue.opacity(departed ? 0.6 : 0), radius: 18)
                }
                .padding(.horizontal, 40)
                .animation(reduced ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: model.stage)
            }
            VStack(spacing: 6) {
                Text(flightTitle).font(.system(size: 20, weight: .semibold))
                Text(flightSubtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460)
            }
            if model.stage == .complete {
                Button("New handoff  ↵") { model.startAgain() }.buttonStyle(RelaySecondaryButton())
            } else if model.stage == .review {
                Button("Back to chats") { model.startAgain() }.buttonStyle(RelaySecondaryButton())
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 46).padding(.horizontal, 24)
    }

    private var departed: Bool { [.departing, .opening, .complete].contains(model.stage) }
    private var flightTitle: String {
        let dest = model.destination.displayName
        switch model.stage {
        case .complete: return model.isFreshSession ? "Fresh \(dest) session ready" : "Opened in " + dest
        case .review: return "Couldn’t open " + dest
        default:
            if model.nativeBusy { return "Reading your conversation…" }
            return model.isFreshSession ? "Starting a fresh \(dest) session…" : "Sending to " + dest
        }
    }
    private var flightSubtitle: String {
        let dest = model.destination.displayName
        switch model.stage {
        case .complete:
            return model.isFreshSession
                ? "Your context is loaded in a fresh \(dest) session — clean window, nothing forgotten. Review it and press Send; Whoosh never submits for you."
                : "Your context is in the new \(dest) composer. Review it and press Send — Whoosh never submits for you."
        case .review: return model.errorMessage ?? "The handoff was prepared but the destination didn’t open."
        default: return "Preserving the conversation and preparing a draft. This takes a moment."
        }
    }

    // MARK: Bits

    private var hintBar: some View {
        HStack(spacing: 18) {
            if flying { key("esc", "Close") }
            else {
                key("↑↓", "Pick")
                key("↵", model.isFreshSession ? "Fresh session" : "Send")
                key("⇥", model.isFreshSession ? "Switch tool" : "Keep here")
                key("esc", "Close")
            }
            Spacer()
            Text("Only the chat you pick moves. Nothing is sent automatically.")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(Color.black.opacity(0.22))
        .overlay(Divider().overlay(Color.white.opacity(0.07)), alignment: .top)
    }

    private func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.58))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.3, blue: 0.3).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.top, 12)
    }

    private func providerIcon(_ app: RelayModel.AgentApp, _ size: CGFloat) -> some View {
        Group {
            if let image = WhooshIdentity.providerIcon(app) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: app == .codex ? "terminal" : "sparkle")
                    .font(.system(size: size * 0.7)).foregroundStyle(.white.opacity(0.8))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct ConversationRow: View {
    let row: RelayModel.NativeThread
    let highlighted: Bool
    let destination: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.bubble.fill").font(.system(size: 15))
                .foregroundStyle(highlighted ? WhooshGeometry.teal : .white.opacity(0.4))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title.isEmpty ? "Untitled conversation" : row.title)
                    .font(.system(size: 15, weight: .medium)).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text(row.projectName).lineLimit(1)
                    if let date = row.updatedAt { Text("·"); Text(Self.activity(date)) }
                }
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            if highlighted {
                HStack(spacing: 5) {
                    Text("Send").font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.turn.down.left").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(WhooshGeometry.teal)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(WhooshGeometry.accent.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(highlighted ? WhooshGeometry.accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WhooshGeometry.accent.opacity(highlighted ? 0.4 : 0), lineWidth: 1))
    }

    static func activity(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
