import XCTest
@testable import IkkunaCore

final class AppRulesTests: XCTestCase {
    func testBundleMappingOverridesNameMappingAndExclusion() {
        XCTAssertEqual(AppRules.shortcut(name: "Finder", bundleID: "com.apple.finder", mappings: ["com.apple.finder": "0", "finder": "f"], ignored: ["finder"]), "0")
    }
    func testMappedKeyIsReservedFromUnmappedInitials() {
        XCTAssertNil(AppRules.shortcut(name: "Bear", bundleID: "bear", mappings: ["firefox": "b"], ignored: []))
    }
    func testIgnoringAnAppOnlyAffectsUnmappedApps() {
        XCTAssertNil(AppRules.shortcut(name: "Finder", bundleID: "com.apple.finder", mappings: [:], ignored: ["com.apple.finder"]))
    }
    func testDefaultInitialMatchesLettersAndDigits() {
        XCTAssertEqual(AppRules.shortcut(name: "1Password", bundleID: "onepassword", mappings: [:], ignored: []), "1")
        XCTAssertEqual(AppRules.shortcut(name: "Slack", bundleID: "slack", mappings: [:], ignored: []), "s")
    }
    func testNonLatinAndPunctuationTitlesUseTab() {
        for title in ["~/project", "", "🪟 Window", "Ääni"] { XCTAssertEqual(AppRules.initial(title), "tab") }
    }
    func testCycleStartsAfterCurrentAppAndWraps() {
        XCTAssertEqual(AppRules.nextIndex(ids: ["a", "b", "c"], current: "a"), 1)
        XCTAssertEqual(AppRules.nextIndex(ids: ["a", "b", "c"], current: "c"), 0)
    }
    func testCycleStartsAtFirstWhenCurrentIsNotAMatch() {
        XCTAssertEqual(AppRules.nextIndex(ids: ["a", "b"], current: "other"), 0)
        XCTAssertNil(AppRules.nextIndex(ids: [], current: "other"))
    }
}
