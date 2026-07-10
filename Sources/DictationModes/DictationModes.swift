import Foundation

/// A user-editable dictation mode: routing rules (which apps/windows trigger it)
/// plus the cleanup-prompt snippet and optional model override it applies.
/// The built-in catalog reproduces the original hardcoded behavior, so a user
/// who never opens the editor gets the same hands-off experience.
public struct DictationModeConfig: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// SF Symbol shown in the recording-pill chip and the editor.
    public var icon: String
    /// Appended to the cleanup system prompt. Soft hints lose to the base
    /// prompt's imperative rules — snippets must be explicit about what they
    /// override (see the dictation-modes wiki page).
    public var promptSnippet: String
    /// Case-insensitive substring matches against the frontmost app's bundle id.
    public var bundleIdentifierMatches: [String]
    /// Case-insensitive substring matches against the focused window's title —
    /// covers web apps (e.g. "gmail" in a browser tab).
    public var windowTitleMatches: [String]
    /// Optional cleanup-model override for this mode; empty uses the app default.
    public var cleanupModel: String
    public var isEnabled: Bool
    /// The fallback mode when nothing matches. Exactly one config should have it.
    public var isFallback: Bool
    /// Built-in modes can be edited but not deleted, and can be restored.
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String,
        promptSnippet: String = "",
        bundleIdentifierMatches: [String] = [],
        windowTitleMatches: [String] = [],
        cleanupModel: String = "",
        isEnabled: Bool = true,
        isFallback: Bool = false,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.promptSnippet = promptSnippet
        self.bundleIdentifierMatches = bundleIdentifierMatches
        self.windowTitleMatches = windowTitleMatches
        self.cleanupModel = cleanupModel
        self.isEnabled = isEnabled
        self.isFallback = isFallback
        self.isBuiltIn = isBuiltIn
    }
}

public enum DictationModeCatalog {
    public static let formalID = "builtin.formal"
    public static let codeID = "builtin.code"
    public static let casualID = "builtin.casual"
    public static let standardID = "builtin.standard"

    /// The four original modes with their tuned snippets and routing. The casual
    /// snippet is the calibrated register from the 2026-06-09 session: keep
    /// everyday punctuation; only the message-final period is dropped.
    public static func builtInModes() -> [DictationModeConfig] {
        [
            DictationModeConfig(
                id: formalID,
                name: "Formal",
                icon: "envelope",
                promptSnippet: "\n\nThis text is going into an email or a formal document. Use complete sentences, correct capitalization and punctuation, and a professional tone. Do not invent a greeting or sign-off that was not spoken.",
                bundleIdentifierMatches: ["mail", "outlook", "spark", "airmail"],
                isBuiltIn: true
            ),
            DictationModeConfig(
                id: codeID,
                name: "Code",
                icon: "chevron.left.forwardslash.chevron.right",
                promptSnippet: "\n\nThis text is going into a code editor or terminal. Preserve code, commands, file paths, symbols, and technical terms exactly as spoken. Do not add prose-style capitalization or trailing punctuation to code. Keep it terse.",
                bundleIdentifierMatches: [
                    "xcode", "terminal", "iterm", "vscode", "cursor", "ghostty",
                    "warp", "sublime", "jetbrains", "nova"
                ],
                isBuiltIn: true
            ),
            DictationModeConfig(
                id: casualID,
                name: "Casual",
                icon: "bubble.left",
                promptSnippet: "\n\nThis is a casual text message (iMessage, SMS, or a chat app). This OVERRIDES the normal-sentence-punctuation rules above where they conflict. Match how the speaker texts a friend: relaxed and informal, but still readable. Keep their normal capitalization, commas, question marks, exclamation points, names, and the word \"I\". The only casual touch is that you may drop the period at the very end of the message. Do not lowercase everything and do not strip out commas or other punctuation. No greeting and no sign-off.",
                bundleIdentifierMatches: [
                    "messages", "mobilesms", "ichat", "slack", "discord",
                    "whatsapp", "telegram", "signal"
                ],
                isBuiltIn: true
            ),
            DictationModeConfig(
                id: standardID,
                name: "Standard",
                icon: "text.alignleft",
                promptSnippet: "",
                isFallback: true,
                isBuiltIn: true
            )
        ]
    }
}

public enum DictationModeResolver {
    /// First enabled mode whose bundle-id or window-title rules match, in array
    /// order (customs are stored ahead of built-ins, so they take priority);
    /// otherwise the enabled fallback mode.
    public static func resolve(
        modes: [DictationModeConfig],
        bundleIdentifier: String?,
        windowTitle: String? = nil
    ) -> DictationModeConfig? {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let title = windowTitle?.lowercased() ?? ""

        for mode in modes where mode.isEnabled && !mode.isFallback {
            if !bundle.isEmpty,
               mode.bundleIdentifierMatches.contains(where: { !$0.isEmpty && bundle.contains($0.lowercased()) }) {
                return mode
            }
            if !title.isEmpty,
               mode.windowTitleMatches.contains(where: { !$0.isEmpty && title.contains($0.lowercased()) }) {
                return mode
            }
        }
        return modes.first(where: { $0.isFallback && $0.isEnabled })
    }
}
