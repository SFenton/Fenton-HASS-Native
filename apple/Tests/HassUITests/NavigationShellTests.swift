import CoreGraphics
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Root navigation: sections, flyout grouping, style choice, navigator intents and split geometry.
@MainActor
struct NavigationShellTests {
    @Test func sectionsMatchTheWebPrimaryNavInOrder() {
        // Owner, 2026-10-16: Settings is the last tab, like the web's.
        #expect(AppSection.allCases.map(\.title) == ["Home", "Security", "Climate", "Chores", "Settings"])
        #expect(AppSection.allCases.map(\.mdiIcon) == ["mdi:home", "mdi:shield", "mdi:thermostat", "mdi:clipboard-list", "mdi:cog"])
        #expect(Set(AppSection.allCases.map(\.navigationIdentifier)).count == AppSection.allCases.count)
    }

    @Test func flyoutListsTheFiveSections() {
        #expect(NavigationMenu.primary == [.home, .security, .climate, .chores, .settings])
        #expect(NavigationMenu.primary == AppSection.allCases)
    }

    @Test func onlyChoresCarriesTheOverdueBadge() {
        #expect(NavigationMenu.badge(for: .chores, overdue: 3) == 3)
        #expect(NavigationMenu.badge(for: .chores, overdue: 0) == nil)
        #expect(NavigationMenu.badge(for: .chores, overdue: nil) == nil)
        #expect(NavigationMenu.badge(for: .home, overdue: 3) == nil)
        #expect(NavigationMenu.accessibilityLabel(for: .chores, overdue: 2) == "Chores, 2 overdue")
        #expect(NavigationMenu.accessibilityLabel(for: .chores, overdue: nil) == "Chores")
        #expect(NavigationMenu.accessibilityLabel(for: .security, overdue: 2) == "Security")
    }

    @Test func styleFollowsHorizontalSizeClassOnly() {
        #expect(ShellNavigationStyle.resolve(isRegularWidth: false) == .tabBar)
        #expect(ShellNavigationStyle.resolve(isRegularWidth: true) == .flyout)
    }

    @Test func navigatorSelectsClosesAndPopsToRoot() {
        let navigator = ShellNavigator()
        navigator.openFlyout()
        #expect(navigator.isFlyoutOpen)
        navigator.select(.climate)
        #expect(navigator.selection == .climate)
        #expect(!navigator.isFlyoutOpen)

        navigator.paths[.climate] = NavigationPath(["detail"])
        #expect(!navigator.isAtRoot(.climate))
        navigator.select(.home)
        #expect(!navigator.isAtRoot(.climate), "switching away keeps the other section's place")
        navigator.select(.climate)
        #expect(!navigator.isAtRoot(.climate))
        navigator.select(.climate)
        #expect(navigator.isAtRoot(.climate), "choosing the current section pops it to its root")
    }

    @Test func dismissingTheFlyoutReturnsFocusOnce() {
        let navigator = ShellNavigator()
        navigator.dismissFlyout()
        #expect(navigator.focusReturnToken == 0, "closing a closed flyout moves nothing")
        navigator.openFlyout()
        navigator.dismissFlyout()
        #expect(navigator.focusReturnToken == 1)
        navigator.openFlyout()
        navigator.select(.security)
        #expect(navigator.focusReturnToken == 1, "choosing a destination does not return focus to the button")
    }

    @Test func pathBindingWritesThroughToTheSection() {
        let navigator = ShellNavigator()
        let binding = navigator.path(for: .chores)
        binding.wrappedValue.append("topic")
        #expect(navigator.paths[.chores]?.count == 1)
        #expect(navigator.isAtRoot(.home))
    }

    @Test func edgeSwipeOpensOnlyFromTheEdgeAndHorizontally() {
        #expect(NavigationFlyoutMetrics.edgeSwipeOpens(startX: 4, translation: CGSize(width: 80, height: 10)))
        #expect(!NavigationFlyoutMetrics.edgeSwipeOpens(startX: 40, translation: CGSize(width: 80, height: 10)))
        #expect(!NavigationFlyoutMetrics.edgeSwipeOpens(startX: 4, translation: CGSize(width: 30, height: 0)))
        #expect(!NavigationFlyoutMetrics.edgeSwipeOpens(startX: 4, translation: CGSize(width: 70, height: 120)))
        #expect(!NavigationFlyoutMetrics.edgeSwipeOpens(startX: 4, translation: CGSize(width: -80, height: 0)))
    }

    @Test func edgeSwipeOpensTheFlyoutOnlyAtASectionRoot() {
        let navigator = ShellNavigator(selection: .chores)
        let swipe = CGSize(width: 80, height: 5)
        navigator.edgeSwipeEnded(startX: 40, translation: swipe)
        #expect(!navigator.isFlyoutOpen)
        navigator.edgeSwipeEnded(startX: 4, translation: swipe)
        #expect(navigator.isFlyoutOpen)
        navigator.dismissFlyout()
        navigator.paths[.chores] = NavigationPath(["topic"])
        navigator.edgeSwipeEnded(startX: 4, translation: swipe)
        #expect(!navigator.isFlyoutOpen, "Deeper pages leave the edge to the system back swipe")
    }
}

/// ``SplitPolicy/geometry(container:isRegularWidth:hinge:)`` per device and pose.
struct SplitGeometryTests {
    @Test func iPadLandscapeSplitsAtTheExactMidpoint() throws {
        let geometry = try #require(SplitPolicy.geometry(
            container: CGRect(x: 0, y: 0, width: 1210, height: 834), isRegularWidth: true, hinge: nil))
        #expect(geometry.leadingWidth == 604.5)
        #expect(geometry.trailingWidth == 604.5)
        #expect(geometry.bandWidth == 1)
        #expect(!geometry.isHinge)
    }

    @Test func duoBookPoseSplitsOnTheHinge() throws {
        let hinge = CGRect(x: 455, y: 0, width: 40, height: 669)
        let geometry = try #require(SplitPolicy.geometry(
            container: CGRect(x: 0, y: 0, width: 951, height: 669), isRegularWidth: true, hinge: hinge))
        #expect(geometry.leadingWidth == 455)
        #expect(geometry.bandWidth == 40)
        #expect(geometry.trailingWidth == 456)
        #expect(geometry.isHinge)
    }

    @Test func horizontalOrOutsideHingesFallBackToTheMidpoint() throws {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let horizontal = CGRect(x: 0, y: 340, width: 1000, height: 20)
        let outside = CGRect(x: 1200, y: 0, width: 20, height: 700)
        #expect(try #require(SplitPolicy.geometry(container: container, isRegularWidth: true, hinge: horizontal)).isHinge == false)
        #expect(try #require(SplitPolicy.geometry(container: container, isRegularWidth: true, hinge: outside)).leadingWidth == 499.5)
    }

    @Test func singlePageLayoutsNeverSplit() {
        let sizes: [(CGSize, Bool)] = [
            (CGSize(width: 402, height: 874), false), // iPhone
            (CGSize(width: 466, height: 678), false), // Duo folded
            (CGSize(width: 678, height: 466), false), // Duo folded, landscape
            (CGSize(width: 669, height: 951), true), // Duo unfolded portrait
            (CGSize(width: 834, height: 1210), true), // iPad portrait
            (CGSize(width: 700, height: 500), true), // narrow landscape window
        ]
        for (size, regular) in sizes {
            #expect(SplitPolicy.geometry(container: CGRect(origin: .zero, size: size), isRegularWidth: regular, hinge: nil) == nil, "\(size)")
        }
    }

    @Test func aHingeLeavingANarrowPaneDoesNotSplit() {
        let hinge = CGRect(x: 200, y: 0, width: 20, height: 700)
        #expect(SplitPolicy.geometry(container: CGRect(x: 0, y: 0, width: 1000, height: 700), isRegularWidth: true, hinge: hinge) == nil)
    }

    @Test func containerOffsetIsMeasuredFromItsOwnEdge() throws {
        let geometry = try #require(SplitPolicy.geometry(
            container: CGRect(x: 100, y: 0, width: 1000, height: 700), isRegularWidth: true, hinge: nil))
        #expect(geometry.leadingWidth == 499.5)
        #expect(geometry.trailingWidth == 499.5)
    }
}

/// Shell chrome placement, the header buttons' sheets and the profile button.
@MainActor
struct ShellChromeTests {
    @Test func menuButtonOnlyUnderTheFlyoutAndTheTitleSharesTheHeaderWithoutIt() {
        // Quick Links and Profile are header buttons on every page; only the menu button and the title placement vary.
        #expect(ShellChrome.resolve(style: .tabBar) == ShellChrome(showsMenuButton: false, titleInHeader: true))
        #expect(ShellChrome.resolve(style: .flyout) == ShellChrome(showsMenuButton: true, titleInHeader: false))
    }

    @Test func headerButtonsPresentTheirSheetsOverTheSelectedSection() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.openFlyout()
        navigator.openQuickLinks()
        #expect(navigator.quickLinksSection == .climate)
        #expect(!navigator.isFlyoutOpen)
        navigator.quickLinksSection = nil
        navigator.openAccount()
        #expect(navigator.accountSection == .climate)
        #expect(navigator.quickLinksSection == nil)
    }

    @Test func settingsIsTheLastTabAndTheFlyoutListsTheSameFive() {
        #expect(AppSection.allCases.last == .settings)
        #expect(NavigationMenu.primary == AppSection.allCases)
        #expect(AppSection.settings.navigationIdentifier == "nav.settings")
    }

    @Test func settingsTopicsPushOnTheSettingsPath() {
        let navigator = ShellNavigator(selection: .settings)
        #expect(navigator.isAtRoot(.settings))
        navigator.paths[.settings, default: NavigationPath()].append(HouseholdSettingsPage.guests)
        #expect(!navigator.isAtRoot(.settings), "a pushed topic leaves the leading edge to the system back swipe")
        navigator.edgeSwipeEnded(startX: 4, translation: CGSize(width: 80, height: 5))
        #expect(!navigator.isFlyoutOpen)
        navigator.select(.settings)
        #expect(navigator.isAtRoot(.settings), "choosing the current tab pops it to its root")
    }

    @Test func profileNamePersistsBetweenLaunches() {
        let saved = UserDefaults.standard.string(forKey: ShellNavigator.profileNameKey)
        defer { UserDefaults.standard.set(saved, forKey: ShellNavigator.profileNameKey) }
        ShellNavigator().profileName = "Stephen Fenton"
        #expect(ShellNavigator().profileName == "Stephen Fenton")
    }

    @Test func profileInitialsTakeTheFirstTwoWords() {
        #expect(ProfileButton.initials("Stephen Fenton") == "SF")
        #expect(ProfileButton.initials("steph") == "S")
        #expect(ProfileButton.initials("Anna Maria Lopez") == "AM")
        #expect(ProfileButton.initials("  ") == nil)
        #expect(ProfileButton.initials(nil) == nil)
    }

    @Test func profileButtonRendersWithAndWithoutAName() {
        #expect(ImageRenderer(content: ProfileButton(name: "Stephen Fenton") {}).cgImage != nil)
        #expect(ImageRenderer(content: ProfileButton(name: nil) {}).cgImage != nil)
        #expect(ImageRenderer(content: ProfileButton(name: "Stephen Fenton", attentionCount: 12) {}).cgImage != nil)
    }

    @Test func profileButtonSpeaksWhoAndWhatNeedsAttention() {
        #expect(ProfileButton.accessibilityValue(name: "Stephen Fenton", attentionCount: 0) == "Stephen Fenton")
        #expect(ProfileButton.accessibilityValue(name: "Stephen Fenton", attentionCount: 1) == "Stephen Fenton, 1 item needs attention")
        #expect(ProfileButton.accessibilityValue(name: nil, attentionCount: 7) == "7 items need attention")
        #expect(ProfileButton.accessibilityValue(name: nil, attentionCount: 0) == "")
    }

    @Test func activeChipsFillWithTheirFamilyAndIdleOnesStayNeutral() {
        #expect(StatusChipStyle.minHeight >= 44)
        #expect(StatusChipStyle.fillFamily(.occupancy, isActive: true) == .occupancy)
        #expect(StatusChipStyle.fillFamily(.occupancy, isActive: false) == nil)
        #expect(StatusChipStyle.fillFamily(nil, isActive: true) == nil)
        #expect(StatusChipStyle.fillFamily(.neutral, isActive: true) == nil)
    }

    @Test func homeChipsFollowTheWebColours() {
        // Security fills with its mode; Climate and Air Quality always fill; the rest only while active.
        #expect(StatusChipView.family(.security, alarmState: "armed_away") == .securityAway)
        #expect(StatusChipView.isFilled(.security, family: .securityDisarmed, isActive: false))
        #expect(!StatusChipView.isFilled(.security, family: nil, isActive: true))
        #expect(StatusChipView.isFilled(.climate, family: .climate, isActive: false))
        #expect(StatusChipView.isFilled(.air, family: .air, isActive: false))
        #expect(!StatusChipView.isFilled(.contact, family: .contact, isActive: false))
        #expect(StatusChipView.isFilled(.light, family: .lights, isActive: true))
        #expect(StatusChipView.family(.presence, alarmState: nil) == .occupancy)
    }

    @Test func chipsRenderFilledAndNeutral() {
        for (family, active) in [(ColorFamily.lights, true), (.climate, true), (.contact, false), (.securityNight, true)] {
            let chip = StatusChipButton(title: "Lights", summary: "3 On", symbol: "lightbulb", family: family,
                                        isActive: active, action: {})
            #expect(ImageRenderer(content: chip).cgImage != nil)
        }
    }
}
