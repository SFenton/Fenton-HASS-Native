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
/// cameras, so journeys never reach the house).
struct SecurityPage: View {
    var caller: any HassServiceCalling
    var canSend: Bool
    var showsCameras: Bool
    var showsVehicle: Bool
    @Environment(EntityStore.self) private var store
    @State private var sheet: SecuritySheet?
    /// Grows with Dynamic Type so tiles drop to fewer columns instead of clipping their titles.
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    /// The Security and Contact Sensors chips (`SECURITY_STATUS_CHIPS`).
    static let chips = HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                StatusRail(chips: Self.chips, idPrefix: "security") { sheet = .chip($0) }
                tileSection("Security", tiles: SecurityConfig.controlTiles)
                    .padding(.horizontal, HassTokens.Spacing.l)
                GuestPresenceSection(caller: caller)
                    .padding(.horizontal, HassTokens.Spacing.l)
                if showsCameras {
                    CameraGrid { sheet = .camera($0) }
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
                if showsVehicle {
                    tileSection("Vehicle", tiles: SecurityConfig.vehicleTiles)
                        .padding(.horizontal, HassTokens.Spacing.l)
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
                    .hassSheet()
            case .contacts:
                RoomOverviewSheet(kind: .contacts)
                    .hassSheet()
            case let .camera(camera):
                CameraViewer(camera: camera)
            }
        }
    }

    private func tileSection(_ title: String, tiles: [SecurityConfig.Tile]) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                ForEach(tiles) { tile in
                    SecurityTile(tile: tile, caller: caller, canSend: canSend) { sheet = .system }
                        .accessibilityIdentifier("security.tile.\(tile.entityId)")
                }
            }
        }
    }
}
