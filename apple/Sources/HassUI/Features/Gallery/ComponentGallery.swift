import HassDesign
import SwiftUI

/// Debug-only component gallery: shows shared controls with fixture data and no server, so UI tests,
/// accessibility audits and screenshots can reach them signed out. Launch with `FENTON_GALLERY=<page>`.
public struct ComponentGallery: View {
    /// A gallery page.
    public enum Page: String, CaseIterable, Sendable {
        case mediaRemote = "media-remote"
        case thermostatDial = "thermostat-dial"
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
        if page == .rooms {
            // Owns its stack so pushed rooms inherit the fixture store and caller.
            RoomsGallery()
        } else {
            NavigationStack {
                switch page {
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
                case .rooms: EmptyView()
                }
            }
        }
    }
}
