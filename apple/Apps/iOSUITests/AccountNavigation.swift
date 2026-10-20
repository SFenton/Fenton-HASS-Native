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

    /// Opens the Your Summary sheet (the web's profile modal) from the profile avatar, then selects `tab`: the app's own
    /// Profile tab by default, where the account, Location and Sign Out are. Pass nil to leave the sheet on the tab it
    /// opens on (Overdue Chores for a resident).
    func openAccountSheet(tab: SummaryTabID? = .profile, file: StaticString = #filePath, line: UInt = #line) {
        let profile = buttons["nav.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "No profile avatar", file: file, line: line)
        profile.tap()
        let close = buttons["account.close"]
        // Right after a signed-in launch the first tap can land while the bar is still settling; tap once more.
        if !close.waitForExistence(timeout: 5), profile.isHittable { profile.tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Account sheet did not open", file: file, line: line)
        if let tab { selectSummaryTab(tab, file: file, line: line) }
    }

    /// Picks a tab of the Your Summary sheet: its segment (icons on compact width, icon over title on regular), or, at
    /// accessibility text sizes, the item of the menu that names the selected section.
    func selectSummaryTab(_ tab: SummaryTabID, file: StaticString = #filePath, line: UInt = #line) {
        let segment = buttons["summary.tabs.\(tab.rawValue)"]
        if segment.waitForExistence(timeout: 3) {
            segment.tap()
            return
        }
        let menu = buttons["summary.tabs"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Summary has neither tab segments nor the tab menu", file: file, line: line)
        menu.tap()
        let item = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tab.title)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(tab.title) in the tab menu", file: file, line: line)
        item.tap()
    }
}

/// A tab of the Your Summary sheet, by the id its segment carries (`summary.tabs.<id>`).
enum SummaryTabID: String, CaseIterable {
    case profile, overdue, upcoming
    case expiredFood = "expired-food"

    var title: String {
        switch self {
        case .profile: "Profile"
        case .overdue: "Overdue Chores"
        case .upcoming: "Upcoming Chores"
        case .expiredFood: "Expired Food"
        }
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
