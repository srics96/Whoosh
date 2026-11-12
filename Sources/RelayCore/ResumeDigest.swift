import Foundation

/// One role-tagged message from a source transcript, used to reconstruct intent for the destination.
public struct ResumeMessage: Sendable {
    public let role: String   // "user" or "assistant"
    public let text: String
    public init(role: String, text: String) { self.role = role; self.text = text }
}

/// A deterministic, no-LLM reconstruction of "where the work is" from a transcript.
///
/// It fills the checkpoint's goal and next step with the user's actual first objective and most
/// recent request (instead of a generic template), and renders a short BRIEF.md so the destination
/// agent can resume immediately instead of re-reading the entire history. The full transcript stays
/// available for depth.
public struct ResumeDigest: Sendable {
    public let goal: String
    public let nextStep: String
    public let brief: String

    private static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n)) + "…"
    }

    public init(title: String, messages: [ResumeMessage], omission: ContextBloat? = nil, sourceBytes: Int? = nil) {
        let cleaned = messages
            .filter { message in
                guard omission == .paste, message.role == "user", let sourceBytes else { return true }
                return !ContextLog.isLargePaste(message.text, minimumBytes: sourceBytes / 4)
            }
            .map { ResumeMessage(role: $0.role, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        let users = cleaned.filter { $0.role == "user" }

        let firstUser = users.first?.text
        let lastUser = users.last?.text
        let lastAssistant = cleaned.last(where: { $0.role == "assistant" })?.text

        goal = Self.clip(firstUser ?? title, 500)
        if let lastUser, firstUser != lastUser {
            nextStep = "Continue from the user's most recent request:\n\"" + Self.clip(lastUser, 700) + "\"\nRead BRIEF.md and confirm the current project state. Look up specific details in the transcript if needed."
        } else {
            nextStep = "Resume the work in progress described in BRIEF.md. Confirm the current project state before changing anything; if the next action is unclear, ask."
        }

        // Render the most recent exchange (what's freshest matters most for resumption).
        let tail = cleaned.suffix(6)
        let decisionPrefixes = ["decision:", "decided ", "we agreed ", "we chose ", "do not ", "must "]
        let earlier = cleaned.dropLast(tail.count).compactMap { message -> String? in
            message.text.split(whereSeparator: \.isNewline).lazy.map {
                String($0).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-*")))
            }.first { line in decisionPrefixes.contains(where: { line.lowercased().hasPrefix($0) }) }
        }.suffix(4).map { "- " + Self.clip($0, 450) }.joined(separator: "\n")
        let omissionNote = omission.map {
            "This brief skips \($0.label). Its source is preserved in the archive; ask the user or look up only the relevant part if needed."
        }
        let recent = tail.map { "**\($0.role == "user" ? "User" : "Assistant")**\n\(Self.clip($0.text, 1500))" }
            .joined(separator: "\n\n")
        brief = """
        # Handoff brief — \(title)

        _Auto-extracted from the transcript at handoff time. Read the full transcript for anything not here._

        ## Original goal
        \(Self.clip(firstUser ?? title, 1200))

        ## Most recent request
        \(lastUser.map { Self.clip($0, 1200) } ?? "No explicit recent user request; continue the in-progress work.")

        ## Assistant's last response
        \(lastAssistant.map { Self.clip($0, 1500) } ?? "None captured.")

        ## Earlier decision excerpts
        \(earlier.isEmpty ? "None detected. Look up specific decisions in the archive as needed." : earlier)

        \(omissionNote ?? "")

        ## Recent exchange
        \(recent.isEmpty ? "None captured." : recent)

        ---
        Messages captured: \(cleaned.count). This brief is a starting point, not a substitute for the transcript.
        """
    }
}
