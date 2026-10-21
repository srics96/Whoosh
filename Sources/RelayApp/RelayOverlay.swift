import SwiftUI
import AppKit
import RelayCore

@MainActor
struct RelayOverlay: View {
    @ObservedObject var model: RelayModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var options = false
    @State private var details = false
    @State private var demo = UserDefaults.standard.bool(forKey: "blinkDesignPreview")
    @State private var demoSelected: RelayModel.NativeThread?
    @State private var demoStage: RelayModel.Stage = .compose
    @State private var demoStopped = false
    @FocusState private var searchFocused: Bool
    private var reduced: Bool { systemReduceMotion || model.reduceMotionInBlink }
    private var stage: RelayModel.Stage { demo ? demoStage : model.stage }
    private var selected: RelayModel.NativeThread? {
        demo ? demoSelected : model.selectingThread ?? model.nativeThreads.first { $0.id == model.nativeSelectedID }
    }
    private var hasSelection: Bool { selected != nil || (!demo && model.conversation != nil) }
    private var departing: Bool { stage == .departing || stage == .opening }
    private var busy: Bool { demo ? [.preparing,.departing,.opening].contains(demoStage) : model.isBusy }
    private var rows: [RelayModel.NativeThread] {
        demo ? [
            .init(id:"preview-a",title:"Polaris — finish the settings experience",preview:"Keyboard navigation is ready. Review the empty state and the final button labels next.",directory:"/preview/Polaris",updatedAt:Date().addingTimeInterval(-180)),
            .init(id:"preview-b",title:"A calmer onboarding flow for first-time users",preview:"The welcome screen is simplified. Keep the account connection optional until it is needed.",directory:"/preview/Orbit",updatedAt:Date().addingTimeInterval(-4200)),
            .init(id:"preview-c",title:"Review search results and keyboard shortcuts",preview:"Search now groups results by project. The remaining work is the focus order.",directory:"/preview/Atlas",updatedAt:Date().addingTimeInterval(-86400))
        ] : model.visibleNativeThreads
    }

    var body: some View {
        VStack(spacing:0) {
            toolbar
            Divider()
            if demo { Text("DESIGN PREVIEW · SYNTHETIC CONTENT · NO APP WILL OPEN").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).padding(.top,10) }
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if let error=model.errorMessage, !demo { message(error,warning:true) }
                    if stage == .complete { completion }
                    else if hasSelection { selection }
                    else { picker }
                }.padding(20)
            }
            footer
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .frame(width:580)
        .font(.system(size:14))
        .popover(isPresented:$options,arrowEdge:.top) { optionPanel }
        .onChange(of:model.source) { _ in searchFocused=true }
    }

    private var toolbar: some View {
        HStack(spacing:12) {
            BlinkMark().frame(width:22,height:20)
            Text("Blink").font(.system(size:14,weight:.semibold))
            Menu {
                ForEach(RelayModel.AgentApp.allCases) { app in Button("From " + app.displayName) { model.chooseSource(app) } }
            } label: {
                HStack(spacing:7) { icon(model.source,20); Text("From " + model.source.displayName); Image(systemName:"chevron.down").font(.system(size:9,weight:.bold)) }
                    .font(.system(size:12,weight:.medium)).padding(.horizontal,10).padding(.vertical,8)
                    .background(.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:9))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy || demo)
            Spacer()
            Button { options.toggle() } label: { Image(systemName:"ellipsis").frame(width:32,height:32) }.buttonStyle(.plain).accessibilityLabel("Options")
            Button(action:close) {
                HStack(spacing:7) { Image(systemName:"xmark").font(.system(size:12,weight:.semibold)); Text("Close"); Text("esc").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary) }
                    .font(.system(size:12,weight:.medium)).padding(.horizontal,12).frame(height:36)
                    .background(.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:9))
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close Blink. Escape also closes.")
        }.padding(.horizontal,20).padding(.vertical,14)
    }

    private var picker: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Choose a conversation to continue in " + model.destination.displayName)
                .font(.system(size:22,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
            Text("Select a chat, then continue in the other app.")
                .font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if demo || model.nativeConnected {
                if !demo {
                    HStack(spacing:9) {
                        Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search conversations or projects",text:$model.nativeSearch).textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit { if let row=rows.first { choose(row) } }
                        Text("↵ review").font(.system(size:11)).foregroundStyle(.secondary)
                    }.padding(12).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:11))
                        .overlay(RoundedRectangle(cornerRadius:11).stroke(.primary.opacity(0.15)))
                        .onAppear { searchFocused=true }
                }
                LazyVStack(spacing:10) {
                    ForEach(rows) { row in Button { choose(row) } label: { rowCard(row) }.buttonStyle(ConversationRowStyle()) }
                }
                if rows.isEmpty { Text(model.nativeSearch.isEmpty ? "No conversations available here yet." : "No conversations match your search.").foregroundStyle(.secondary).padding(.vertical,20) }
                if !demo && model.nativeNextCursor != nil { Button("Show more conversations",action:model.loadMoreNativeThreads).disabled(model.nativeBusy) }
            } else if model.nativeBusy {
                HStack(spacing:10) { ProgressView().controlSize(.small); Text("Loading your conversations…") }.padding(.vertical,28)
            } else {
                Text("Connect once to see local " + model.source.displayName + " conversations. Blink reads only the chat you choose.")
                    .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Button("Connect " + model.source.displayName) { model.reconnectNativeCodex() }.buttonStyle(.borderedProminent).controlSize(.large)
                if model.source == .claude { Text("Local Code sessions only. Claude Chat and Cowork aren’t available here.").font(.system(size:12)).foregroundStyle(.secondary) }
            }
        }
    }

    private func rowCard(_ row:RelayModel.NativeThread) -> some View {
        HStack(alignment:.top,spacing:16) {
            Image(systemName:"text.bubble").font(.system(size:19)).foregroundStyle(.secondary).frame(width:24).padding(.top,3)
            VStack(alignment:.leading,spacing:5) {
                Text(row.title).font(.system(size:16,weight:.semibold)).lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                metadata(row)
                if !row.preview.isEmpty && row.preview != row.title { Text(row.preview).font(.system(size:13)).foregroundStyle(.secondary).lineLimit(1).multilineTextAlignment(.leading) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            VStack(spacing:8) { Image(systemName:"arrow.up.right").font(.system(size:13,weight:.semibold)); Text("Review").font(.system(size:10,weight:.medium)) }.foregroundStyle(.secondary).padding(.top,5)
        }.padding(13).frame(maxWidth:.infinity,alignment:.leading)
    }
    private func metadata(_ row:RelayModel.NativeThread) -> some View {
        HStack(spacing:6) {
            Image(systemName:"folder").font(.system(size:11))
            Text(row.projectName).lineLimit(1)
            if let date=row.updatedAt { Text("·"); Text(activityLabel(date)) }
        }.font(.system(size:12)).foregroundStyle(.secondary)
    }
    private func activityLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    private func choose(_ row:RelayModel.NativeThread) {
        searchFocused=false
        if demo { withAnimation(.easeInOut(duration:0.18)) { demoSelected=row } }
        else { model.selectNativeThread(row.id) }
    }

    private var selection: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Button { if demo { demoSelected=nil; demoStage = .compose } else { model.startAgain() } } label: { Label("Conversations",systemImage:"chevron.left") }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(busy)
                Spacer()
                icon(model.destination,28)
                Text(model.destination.displayName).font(.system(size:14,weight:.semibold))
            }
            Text(stage == .compose ? "Continue where you left off" : stage == .departing ? "Bringing your context along" : "Preparing your conversation")
                .font(.system(size:24,weight:.semibold))
            VStack(alignment:.leading,spacing:14) {
                HStack { icon(model.source,24); Text(model.source.displayName).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary); Spacer(); Image(systemName:"text.bubble").foregroundStyle(.secondary) }
                Text(selected?.title ?? model.conversationDisplayName ?? "Selected conversation").font(.system(size:22,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                if let row=selected { metadata(row); if !row.preview.isEmpty && row.preview != row.title { Text(row.preview).font(.system(size:14)).foregroundStyle(.secondary).lineLimit(3) } }
            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18).stroke(.primary.opacity(0.13)))
                .shadow(color:.black.opacity(stage == .departing ? 0.02 : 0.1),radius:18,y:8)
                .scaleEffect(departing && !reduced ? 0.76 : 1,anchor:.topTrailing)
                .offset(x:departing && !reduced ? 120 : 0,y:departing && !reduced ? -65 : 0)
                .opacity(departing ? 0 : 1)
                .animation(.easeIn(duration:reduced ? 0.14 : 0.28),value:stage)
            if busy {
                HStack(spacing:10) {
                    ProgressView().controlSize(.small)
                    Text(model.nativeBusy ? "Reading the conversation and checking its context…" : stage == .opening ? "Waiting for macOS to open the destination…" : stage == .departing ? "Context saved. Opening the destination…" : model.phase.rawValue)
                        .font(.system(size:14)).foregroundStyle(.secondary)
                }
                if !demo && model.canCancelSourceRead { Button("Cancel reading",action:model.cancelSourceRead) }
                else if stage == .preparing || stage == .departing { Button("Cancel") { if demo { demoStage = .compose } else { model.cancelPreparation() } } }
            } else if stage == .compose {
                if !demo && model.sensitiveContentBlocked { message("Possible sensitive data was found. Review it in Details before continuing.",warning:true) }
                if !demo && model.projectURL == nil && model.conversation != nil { Button("Choose the missing project folder…") { model.chooseFolder(output:false) }.buttonStyle(.bordered) }
                if demo || (!model.sourceIdleKnown && model.conversation != nil) {
                    Toggle(isOn:demo ? $demoStopped : $model.sourceStopped) { Text("The source has finished working").font(.system(size:14,weight:.medium)) }.toggleStyle(.checkbox)
                    Text("Blink can’t verify whether this source is still working. Stop it there before continuing.").font(.system(size:12)).foregroundStyle(.secondary)
                }
                if !demo && model.conversation?.isPartial == true { message("This export doesn’t include every kind of source content. See Details for what’s missing.",warning:true) }
                if !demo { DisclosureGroup("Add an instruction (optional)") { TextField("What should happen next?",text:$model.userInstruction,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...4).padding(.top,8) }.font(.system(size:13)) }
                Text("A new draft will open in " + model.destination.displayName + ". Review it and press Send there. File access may need its approval.").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !demo { DisclosureGroup("Details",isExpanded:$details) {
                    VStack(alignment:.leading,spacing:10) {
                        Text(model.conversationNotice ?? "No archive loaded.")
                        Text(model.conversation?.preview ?? "").font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                    }.font(.system(size:12)).foregroundStyle(.secondary).padding(.top,8)
                }.font(.system(size:12)) }
            } else if stage == .review {
                message("The files are preserved, but the destination did not open. Check the error above before trying again.",warning:true)
                Button("Return to conversation",action:model.editCheckpoint)
            }
        }
    }

    private var completion: some View {
        VStack(alignment:.leading,spacing:22) {
            icon(model.destination,42)
            Text(demo ? "Preview complete" : "Check your draft in " + model.destination.displayName).font(.system(size:25,weight:.semibold))
            Text(demo ? "This demonstrated the transition only. No app opened and no context was sent." : "macOS accepted the open request. Review the draft in the other app and press Send to continue. Blink cannot verify that it read the archive.")
                .font(.system(size:15)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button(demo ? "Back to preview" : "Choose another conversation") { if demo { demoSelected=nil; demoStage = .compose; demoStopped=false } else { model.startAgain() } }.buttonStyle(.bordered)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,30)
    }
    private var footer: some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            if hasSelection && stage == .compose {
                if let blocker = demo ? (demoStopped ? nil : "Confirm the source is stopped to continue.") : model.selectionBlocker { Text(blocker).font(.system(size:12)).foregroundStyle(.secondary) }
                Button {
                    if demo { runPreview() } else { model.continueHandoff() }
                } label: {
                    HStack { icon(model.destination,24); Text("Continue in " + model.destination.displayName).font(.system(size:16,weight:.semibold)); Spacer(); Text("↵").font(.system(size:18)) }.padding(.horizontal,16).frame(height:52).frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(demo ? !demoStopped : !model.canPrepare)
                Text("Only this selected conversation is shared. Nothing is submitted automatically.").font(.system(size:11)).foregroundStyle(.secondary)
            } else if !hasSelection { Text("Choose a conversation to review it. Nothing opens yet.").font(.system(size:12)).foregroundStyle(.secondary) }
            else { Text("Esc closes Blink. No automatic submission.").font(.system(size:12)).foregroundStyle(.secondary) }
        }.padding(.horizontal,24).padding(.bottom,20)
    }
    private var optionPanel: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Options").font(.headline); Spacer(); Button("Done") { options=false } }
            Button("Switch direction",action:model.swapApps).disabled(busy || demo)
            if model.nativeConnected { Button("Disconnect " + model.source.displayName,action:model.disconnectNativeCodex).disabled(busy) }
            Toggle("Reduce motion in Blink",isOn:$model.reduceMotionInBlink)
            Divider()
            DisclosureGroup("Advanced") {
                VStack(alignment:.leading,spacing:12) {
                    Button("Import a conversation export…",action:model.importConversation)
                    Button("Locate Codex helper…",action:model.connectNativeCodex)
                    Toggle("Include owned Blink test chats",isOn:$model.includeOwnedTestChats)
                    Button(demo ? "Exit design preview" : "Design preview (synthetic)") { demo.toggle(); UserDefaults.standard.set(demo, forKey:"blinkDesignPreview"); demoSelected=nil; demoStage = .compose; demoStopped=false; options=false }
                    Text("Exact active-chat detection isn’t available through these connections. Blink uses a picker; it never guesses from recency.").font(.system(size:12)).foregroundStyle(.secondary)
                }.padding(.top,12)
            }
        }.padding(20).frame(width:360)
    }
    private func runPreview() {
        demoStage = .preparing
        Task {
            try? await Task.sleep(nanoseconds:400_000_000)
            guard demoStage == .preparing else { return }
            demoStage = .departing
            try? await Task.sleep(nanoseconds:reduced ? 140_000_000 : 340_000_000)
            guard demoStage == .departing else { return }
            demoStage = .complete
        }
    }
    private func icon(_ app:RelayModel.AgentApp,_ size:CGFloat) -> some View {
        Group { if let image=BlinkIdentity.providerIcon(app) { Image(nsImage:image).resizable().aspectRatio(contentMode:.fit) } else { Image(systemName:"app") } }.frame(width:size,height:size).accessibilityHidden(true)
    }
    private func message(_ text:String,warning:Bool) -> some View {
        Label(text,systemImage:warning ? "exclamationmark.circle" : "info.circle").font(.system(size:13)).fixedSize(horizontal:false,vertical:true).padding(13).frame(maxWidth:.infinity,alignment:.leading).background(Color.orange.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
    }
}
private struct ConversationRowStyle: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.background(Color(nsColor:.controlBackgroundColor).opacity(configuration.isPressed ? 0.55 : 1),in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).stroke(.primary.opacity(configuration.isPressed ? 0.28 : 0.10)))
            .contentShape(RoundedRectangle(cornerRadius:13))
    }
}
