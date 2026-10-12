import HassDesign
import SwiftUI

/// Debug-only component gallery: shows shared controls with fixture data and no server, so UI tests,
/// accessibility audits and screenshots can reach them signed out. Launch with `FENTON_GALLERY=<page>`.
public struct ComponentGallery: View {
    /// A gallery page.
    public enum Page: String, CaseIterable, Sendable {
        case mediaRemote = "media-remote"
        case thermostatDial = "thermostat-dial"
        case floatingActions = "floating-actions"
        case inventory
        case vacuums
        case roomDevices = "room-devices"
        case householdSettings = "household-settings"
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
        NavigationStack {
            switch page {
            case .mediaRemote: MediaRemoteGallery()
            case .thermostatDial: ThermostatDialGallery()
            case .floatingActions: FloatingActionsGallery()
            case .inventory:
                #if DEBUG
                InventoryGallery()
                #else
                EmptyView()
                #endif
            case .vacuums: VacuumGallery()
            case .roomDevices: RoomDevicesGallery()
            case .householdSettings: HouseholdSettingsGallery()
            }
        }
    }
}
