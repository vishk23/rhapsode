import XCTest
@testable import DictationModeKit

final class DictationModeResolverTests: XCTestCase {
    private let builtIns = DictationModeCatalog.builtInModes()

    // MARK: Characterization — routing must match the original hardcoded chain

    func testMailRoutesToFormal() {
        XCTAssertEqual(
            DictationModeResolver.resolve(modes: builtIns, bundleIdentifier: "com.apple.mail")?.id,
            DictationModeCatalog.formalID
        )
    }

    func testXcodeAndTerminalRouteToCode() {
        for bundle in ["com.apple.dt.Xcode", "com.googlecode.iterm2", "com.apple.Terminal"] {
            XCTAssertEqual(
                DictationModeResolver.resolve(modes: builtIns, bundleIdentifier: bundle)?.id,
                DictationModeCatalog.codeID, bundle
            )
        }
    }

    func testMessagesAndSlackRouteToCasual() {
        for bundle in ["com.apple.MobileSMS", "com.tinyspeck.slackmacgap"] {
            XCTAssertEqual(
                DictationModeResolver.resolve(modes: builtIns, bundleIdentifier: bundle)?.id,
                DictationModeCatalog.casualID, bundle
            )
        }
    }

    func testUnknownAppFallsBackToStandard() {
        XCTAssertEqual(
            DictationModeResolver.resolve(modes: builtIns, bundleIdentifier: "com.example.unknown")?.id,
            DictationModeCatalog.standardID
        )
        XCTAssertEqual(
            DictationModeResolver.resolve(modes: builtIns, bundleIdentifier: nil)?.id,
            DictationModeCatalog.standardID
        )
    }

    // MARK: New capabilities

    func testDisabledModeIsSkipped() {
        var modes = builtIns
        modes[0].isEnabled = false // Formal off
        XCTAssertEqual(
            DictationModeResolver.resolve(modes: modes, bundleIdentifier: "com.apple.mail")?.id,
            DictationModeCatalog.standardID
        )
    }

    func testCustomModeAheadOfBuiltInWins() {
        let custom = DictationModeConfig(
            name: "Work Slack",
            icon: "briefcase",
            promptSnippet: "\n\nProfessional but friendly.",
            bundleIdentifierMatches: ["slack"]
        )
        let modes = [custom] + builtIns
        XCTAssertEqual(
            DictationModeResolver.resolve(modes: modes, bundleIdentifier: "com.tinyspeck.slackmacgap")?.id,
            custom.id
        )
    }

    func testWindowTitleKeywordMatchesWebApps() {
        let gmail = DictationModeConfig(
            name: "Gmail",
            icon: "envelope",
            windowTitleMatches: ["gmail"]
        )
        let modes = [gmail] + builtIns
        XCTAssertEqual(
            DictationModeResolver.resolve(
                modes: modes,
                bundleIdentifier: "com.google.Chrome",
                windowTitle: "Inbox (3) - vk@example.com - Gmail"
            )?.id,
            gmail.id
        )
    }

    // MARK: Casual register contract — the calibrated snippet must not regress

    func testCasualSnippetKeepsPunctuationRules() {
        let casual = builtIns.first { $0.id == DictationModeCatalog.casualID }!
        XCTAssertTrue(casual.promptSnippet.contains("Do not lowercase everything"))
        XCTAssertTrue(casual.promptSnippet.contains("drop the period at the very end"))
        XCTAssertTrue(casual.promptSnippet.contains("OVERRIDES"))
        XCTAssertTrue(casual.promptSnippet.contains("No greeting and no sign-off"))
    }

    func testExactlyOneFallbackMode() {
        XCTAssertEqual(builtIns.filter(\.isFallback).count, 1)
    }
}
