import XCTest

extension XCUIApplication {
    /// Opens Settings the direction G way: the profile avatar on a tab root opens the Account sheet, and Settings
    /// is pushed inside it (`.agents/design/direction-g.md`, Navigation).
    func openAccountSettings(file: StaticString = #filePath, line: UInt = #line) {
        openAccountSheet(file: file, line: line)
        let row = buttons["account.settings"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Account sheet has no Settings row", file: file, line: line)
        row.tap()
        XCTAssertTrue(navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open", file: file, line: line)
    }

    /// Opens the Account sheet from the profile avatar.
    func openAccountSheet(file: StaticString = #filePath, line: UInt = #line) {
        let profile = buttons["nav.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "No profile avatar", file: file, line: line)
        profile.tap()
        let close = buttons["account.close"]
        // Right after a signed-in launch the first tap can land while the bar is still settling; tap once more.
        if !close.waitForExistence(timeout: 5), profile.isHittable { profile.tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Account sheet did not open", file: file, line: line)
    }
}

extension XCUIApplication {
    /// The Settings list inside the Account sheet. The sheet's presenting page stays in the hierarchy, so the
    /// first collection view is not always Settings.
    var settingsList: XCUIElement {
        let list = collectionViews["settings.list"]
        // Right after a sheet over Settings closes, the list can take a moment to come back.
        return list.waitForExistence(timeout: 3) ? list : collectionViews.firstMatch
    }
}
