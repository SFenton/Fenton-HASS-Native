import CoreGraphics
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Root navigation: sections, flyout grouping, style choice, navigator intents and split geometry.
@MainActor
struct NavigationShellTests {
    @Test func sectionsMatchTheWebPrimaryNavInOrder() {
        // Direction G: four tabs; Settings lives in the Account sheet.
        #expect(AppSection.allCases.map(\.title) == ["Home", "Security", "Climate", "Chores"])
        #expect(AppSection.allCases.map(\.mdiIcon) == ["mdi:home", "mdi:shield", "mdi:thermostat", "mdi:clipboard-list"])
        #expect(Set(AppSection.allCases.map(\.navigationIdentifier)).count == AppSection.allCases.count)
    }

    @Test func flyoutListsTheFourSections() {
        #expect(NavigationMenu.primary == [.home, .security, .climate, .chores])
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

/// The compact tab bar layout, shell chrome placement, Quick Links tab selection and the profile button.
@MainActor
struct ShellChromeTests {
    @Test func iOS26CompactBarAddsTheQuickLinksCircle() {
        #expect(CompactTabLayout.resolve(supportsTrailingTab: true) == .sectionsWithQuickLinks)
        #expect(CompactTabLayout.resolve(supportsTrailingTab: true).hasQuickLinksTab)
        #expect(!CompactTabLayout.resolve(supportsTrailingTab: false).hasQuickLinksTab)
    }

    @Test func menuButtonOnlyUnderTheFlyoutQuickLinksButtonWhereThereIsNoCircleAndFloatingCircleInRegularWidth() {
        #expect(ShellChrome.resolve(style: .tabBar, layout: .sectionsWithQuickLinks)
            == ShellChrome(showsMenuButton: false, showsQuickLinksButton: false))
        #expect(ShellChrome.resolve(style: .tabBar, layout: .sectionsOnly)
            == ShellChrome(showsMenuButton: false, showsQuickLinksButton: true))
        #expect(ShellChrome.resolve(style: .flyout, layout: .sectionsWithQuickLinks)
            == ShellChrome(showsMenuButton: true, showsQuickLinksButton: false, showsFloatingQuickLinks: true))
        #expect(!ShellChrome.resolve(style: .tabBar, layout: .sectionsOnly).showsFloatingQuickLinks)
    }

    @Test func quickLinksTabSitsOverTheSelectedSection() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.paths[.climate] = NavigationPath(["room"])
        navigator.rootTab = .quickLinks
        #expect(navigator.isQuickLinksActive)
        #expect(navigator.selection == .climate)
        // Returning to the section under Quick Links keeps its stack.
        navigator.select(.climate)
        #expect(!navigator.isQuickLinksActive)
        #expect(navigator.paths[.climate]?.count == 1)
        navigator.rootTab = .quickLinks
        navigator.closeQuickLinks()
        #expect(navigator.rootTab == .section(.climate))
    }

    @Test func flyoutAndToolbarPresentTheQuickLinksSheetOverTheSelectedSection() {
        let navigator = ShellNavigator(selection: .home)
        navigator.openFlyout()
        navigator.openQuickLinks()
        #expect(navigator.quickLinksSection == .home)
        #expect(!navigator.isFlyoutOpen)
        #expect(navigator.rootTab == .section(.home))
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
    }

    @Test func activeChipsFillWithTheirFamilyAndIdleOnesStayNeutral() {
        #expect(StatusChipStyle.minHeight >= 44)
        #expect(StatusChipStyle.fillFamily(.occupancy, isActive: true) == .occupancy)
        #expect(StatusChipStyle.fillFamily(.occupancy, isActive: false) == nil)
        #expect(StatusChipStyle.fillFamily(nil, isActive: true) == nil)
        #expect(StatusChipStyle.fillFamily(.neutral, isActive: true) == nil)
    }

    @Test func chipTintsWinOverTheFamilyAndAnimateOnlyColour() {
        // A computed tint (temperature, AQI, contact state) fills the chip even when its family would leave it neutral.
        #expect(StatusChipStyle.fillTint(.contact, isActive: false, tint: .contactOpenAway) == .contactOpenAway)
        #expect(StatusChipStyle.fillTint(.contact, isActive: false, tint: nil) == nil)
        #expect(StatusChipStyle.fillTint(.occupancy, isActive: true, tint: nil) == ChipTint(family: .occupancy))
        #expect(StatusChipStyle.fillTint(.neutral, isActive: true, tint: nil) == nil)
        // Reduce Motion keeps a colour cross-fade (HIG, Motion), only shorter.
        #expect(StatusChipStyle.colorAnimation(reduceMotion: true) != StatusChipStyle.colorAnimation(reduceMotion: false))
    }

    @Test func chipsRenderFilledAndNeutral() {
        for (family, active) in [(ColorFamily.lights, true), (.climate, true), (.contact, false), (.securityNight, true)] {
            let chip = StatusChipButton(title: "Lights", summary: "3 On", symbol: "lightbulb", family: family,
                                        isActive: active, action: {})
            #expect(ImageRenderer(content: chip).cgImage != nil)
            let tinted = StatusChipButton(title: "Climate", summary: "72°F", symbol: "thermometer", family: family,
                                          isActive: active, tint: ChipTint.fromWeb(0xFFD700), action: nil)
            #expect(ImageRenderer(content: tinted).cgImage != nil)
        }
    }
}
