import XCTest

extension XCUIApplication {
    /// Opens Settings, which is the last tab of the shell (owner, 2026-10-16; `.agents/design/direction-g.md`,
    /// Navigation): its bar item in compact width (the folded Duo's vertical bar is a toolbar to XCUITest), else its row
    /// in the flyout. Does nothing when the Settings list is already showing.
    func openAccountSettings(file: StaticString = #filePath, line: UInt = #line) {
        if descendants(matching: .any).matching(identifier: "settings.list").firstMatch.exists, navigationBars["Settings"].exists { return }
        let items = [tabBars.buttons["Settings"], toolbars.buttons["Settings"]]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let item = items.first(where: { $0.exists && $0.isHittable }) {
                item.tap()
                break
            }
            // Regular width has no bar: Open Navigation, then the Settings row.
            let menu = buttons["nav.open"]
            if menu.exists, menu.isHittable, !items.contains(where: \.exists) {
                menu.tap()
                let row = buttons["nav.settings"]
                XCTAssertTrue(row.waitForExistence(timeout: 5), "Flyout has no Settings row", file: file, line: line)
                row.tap()
                break
            }
            usleep(250_000)
        }
        XCTAssertTrue(navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open", file: file, line: line)
    }

    /// Opens the Account sheet (the web's profile modal, Your Summary) from the profile avatar.
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
    /// The Settings list. Matched by identifier on any element type: after a form over it closes, the list isn't
    /// always exposed as a collection view.
    var settingsList: XCUIElement {
        let list = descendants(matching: .any).matching(identifier: "settings.list").firstMatch
        // Right after a sheet over Settings closes, the list can take a moment to come back.
        return list.waitForExistence(timeout: 3) ? list : collectionViews.firstMatch
    }
}
