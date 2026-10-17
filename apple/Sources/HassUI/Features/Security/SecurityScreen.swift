import HassCore
import HassDesign
import SwiftUI

/// The Security tab (web `SecurityDashboard.tsx`). Spec: `.agents/pages/security/spec.md`.
struct SecurityScreen: View {
    @Environment(HassConnection.self) private var connection

    var body: some View {
        SecurityPage(
            caller: connection,
            canSend: Self.canSend(connection.status),
            showsCameras: true,
            showsVehicle: SecurityConfig.showsVehicleSection
        )
    }

    /// Whether a command can go out now (web `connectionCannotSend`: not while disconnected or suspended).
    static func canSend(_ status: HassConnection.Status) -> Bool {
        switch status {
        case .connected, .connecting: true
        case .disconnected, .waitingToReconnect, .rejected: false
        }
    }
}

/// Sheets presented from Security (web hash modals).
enum SecuritySheet: Identifiable, Hashable {
    case system
    case contacts
    case camera(HomeConfig.Camera)

    var id: String {
        switch self {
        case .system: "system"
        case .contacts: "contacts"
        case let .camera(camera): "camera-\(camera.entityId)"
        }
    }

    /// The sheet a status chip opens.
    static func chip(_ kind: HomeConfig.ChipSheet) -> SecuritySheet {
        kind == .security ? .system : .contacts
    }
}

/// The page body, shared by ``SecurityScreen`` and the debug gallery (which passes a recording caller and no
/// cameras, so journeys never reach the house). Direction G mockup n3: the status chips, the alarm card, the Doors
/// tiles, guests, cameras and the car.
struct SecurityPage: View {
    var caller: any HassServiceCalling
    var canSend: Bool
    var showsCameras: Bool
    var showsVehicle: Bool
    @State private var sheet: SecuritySheet?
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    /// The Security and Contact Sensors chips (`SECURITY_STATUS_CHIPS`).
    static let chips = HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) }

    /// The locks and garage doors, in web order (the alarm tile became the card above them).
    static let doorTiles = SecurityConfig.controlTiles.filter { $0.kind != .alarm }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                    StatusRail(chips: Self.chips, idPrefix: "security") { sheet = .chip($0) }
                    AlarmPanel(caller: caller)
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
                doorSection("Doors", tiles: Self.doorTiles)
                GuestPresenceSection(caller: caller)
                    .padding(.horizontal, HassTokens.Spacing.l)
                if showsCameras {
                    CameraGrid(idPrefix: "security.camera") { sheet = .camera($0) }
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
                if showsVehicle {
                    doorSection("Mach-E", tiles: SecurityConfig.vehicleTiles)
                }
            }
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Security")
        .accessibilityIdentifier("security.scroll")
        .navigationTitle("Security")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { FreshnessIndicator() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .system:
                SecuritySystemSheet(caller: caller)
                    .hassSheet(.page)
            case .contacts:
                RoomOverviewSheet(kind: .contacts)
                    .hassSheet(.page, height: .full) // Navigates to a room group
            case let .camera(camera):
                CameraViewer(camera: camera)
            }
        }
    }

    /// A titled grid of lock and garage door tiles (owner, 2026-10-16: doors as tiles, not rows). Tiles in the grid share
    /// one height, set by the tallest, and reflow to one column at accessibility sizes.
    private func doorSection(_ title: String, tiles: [SecurityConfig.Tile]) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s + 2) {
            RoomSectionHeader(title: title)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                ForEach(tiles) { tile in
                    SecurityDoorTile(tile: tile, caller: caller, canSend: canSend)
                }
            }
            .equalHeightTiles()
        }
        .padding(.horizontal, HassTokens.Spacing.l)
    }
}
