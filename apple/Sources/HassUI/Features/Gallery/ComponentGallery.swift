import HassCore
import HassDesign
import SwiftUI

/// Debug-only component gallery: shows shared controls with fixture data and no server, so UI tests,
/// accessibility audits and screenshots can reach them signed out. Launch with `FENTON_GALLERY=<page>`.
public struct ComponentGallery: View {
    /// A gallery page.
    public enum Page: String, CaseIterable, Sendable {
        case food
        case mediaRemote = "media-remote"
        case thermostatDial = "thermostat-dial"
        case vacation
        case security
        case rooms
        case mediaPage = "media-page"
        case customLights = "custom-lights"
        case sprinklers
        case bedroom = "bedroom"
        case vacuums
        case roomDevices = "room-devices"
        case householdSettings = "household-settings"
        case climate
        case floatingActions = "floating-actions"
        case inventory
        case chores
        case settings
        case performance
        case weather
        case directionG = "direction-g"
        case location
        case systemAccessibility = "system-accessibility"
        case modalSizing = "modal-sizing"
        case liveActivity = "live-activity"
        case profile
        /// An empty page: only the wallpaper and its scrim (with `FENTON_BACKDROP_FIXTURE=1`), for screenshots.
        case backdrop
        case shellHeader = "shell-header"
    }

    /// The page requested at launch, if any. Always `nil` in release builds.
    public static var requested: Page? {
        #if DEBUG
        ProcessInfo.processInfo.environment["FENTON_GALLERY"].flatMap(Page.init(rawValue:))
        #else
        nil
        #endif
    }

    public var page: Page

    /// Creates the gallery on `page`.
    public init(page: Page) { self.page = page }

    public var body: some View {
        // Every gallery file is compiled into Debug builds only; release builds never show a gallery.
        #if DEBUG
        pages.modifier(GalleryBackdrop())
        #else
        EmptyView()
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private var pages: some View {
        if page == .food {
            // Owns its navigation stack so journeys can start on a pushed page.
            FoodGallery()
        } else if page == .chores {
            // Owns its stack so pushed todo pages inherit the fixture store and model.
            ChoresGallery()
        } else if page == .settings {
            // The Settings tab's root as the app's section stack hosts it (page chrome included), on fixtures.
            SettingsGallery()
        } else if page == .vacation {
            // Owns its stack, so its last-call line stays under pushed pages too.
            VacationGallery()
        } else if page == .location {
            // Presents its own sheet, which owns its navigation stack.
            LocationGallery()
        } else if page == .shellHeader {
            // Owns its stack, so the header buttons sit in the real navigation bar and a pushed page shows Back.
            ShellHeaderGallery()
        } else if page == .profile {
            // Presents its own sheet (Your Summary), which owns its navigation stack.
            ProfileGallery()
        } else if page == .rooms {
            // Owns its stack so pushed rooms inherit the fixture store and caller.
            RoomsGallery()
        } else {
            NavigationStack {
                Group {
                    switch page {
                    case .directionG: DirectionGGallery()
                    case .mediaRemote: MediaRemoteGallery()
                    case .thermostatDial: ThermostatDialGallery()
                    case .security: SecurityGallery()
                    case .mediaPage: HomePageGallery(kind: .media)
                    case .customLights: HomePageGallery(kind: .customLights)
                    case .sprinklers: HomePageGallery(kind: .sprinklers)
                    case .bedroom: BedroomGallery()
                    case .vacuums: VacuumGallery()
                    case .roomDevices: RoomDevicesGallery()
                    case .householdSettings: HouseholdSettingsGallery()
                    case .climate: ClimateGallery()
                    case .floatingActions: FloatingActionsGallery()
                    case .inventory: InventoryGallery()
                    case .performance: PerformanceGallery()
                    case .weather: WeatherGallery()
                    case .systemAccessibility: SystemAccessibilityGallery()
                    case .modalSizing: ModalSizingGallery()
                    case .liveActivity: LiveActivityGallery()
                    case .backdrop: BackdropOnlyPage()
                    case .rooms, .vacation, .food, .chores, .location, .settings, .shellHeader, .profile: EmptyView()
                    }
                }
                // Direction G: a gallery page sits on the same dark house backdrop as the page it stands in for.
                // On the system's white ground, G's translucent tiles measured 3.1:1.
                .scrollContentBackground(.hidden)
                .pageBackdrop()
            }
            .preferredColorScheme(.dark)
        }
    }
    #endif
}

#if DEBUG
/// With `FENTON_BACKDROP_FIXTURE=1` a gallery gets the same wallpaper as the shell: the fixture store, and the window
/// measured for it, so journeys and the scroll cost probe see the photo, the Background Blur setting and the real
/// render path. Without it a gallery draws the plain base, as before.
private struct GalleryBackdrop: ViewModifier {
    @State private var store = HouseBackdropStore.fixture(for: HassServer(baseURL: URL(string: "https://gallery.invalid")!))

    func body(content: Content) -> some View {
        if let store {
            content
                .backdropCanvasProvider()
                .environment(store)
                .task { await store.refresh() }
        } else {
            content
        }
    }
}
#endif

#if DEBUG
/// A page with nothing on it: the wallpaper and its scrim and no navigation bar (`FENTON_GALLERY=backdrop`).
private struct BackdropOnlyPage: View {
    var body: some View {
        #if os(iOS)
        Color.clear.toolbar(.hidden, for: .navigationBar)
        #else
        Color.clear
        #endif
    }
}
#endif
