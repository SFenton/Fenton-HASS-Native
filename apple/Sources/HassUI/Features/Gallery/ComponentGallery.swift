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
        case performance
        case weather
        case directionG = "direction-g"
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
        pages
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
        } else if page == .vacation {
            // Owns its stack, so its last-call line stays under pushed pages too.
            VacationGallery()
        } else if page == .rooms {
            // Owns its stack so pushed rooms inherit the fixture store and caller.
            RoomsGallery()
        } else {
            NavigationStack {
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
                case .rooms, .vacation, .food, .chores: EmptyView()
                }
            }
        }
    }
    #endif
}
