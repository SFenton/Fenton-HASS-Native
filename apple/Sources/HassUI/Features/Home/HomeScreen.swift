import HassCore
import HassDesign
import SwiftUI

/// Home (web At a Glance overview). Spec: `.agents/pages/home/spec.md`.
struct HomeScreen: View {
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.roomServiceCaller) private var callerOverride
    @State private var sheet: HomeSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                StatusRail { sheet = .chip($0) }
                WeatherSummaryCard()
                    .padding(.horizontal, HassTokens.Spacing.l)
                GuestPresenceSection()
                    .padding(.horizontal, HassTokens.Spacing.l)
                CameraGrid { sheet = .camera($0) }
                    .padding(.horizontal, HassTokens.Spacing.l)
            }
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .scrollTelemetry("Home")
        .accessibilityIdentifier("home.scroll")
        .navigationTitle("Home")
        .foodNavigation()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { FreshnessIndicator() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .chip(kind):
                chipSheet(kind)
                    .hassSheet()
            case let .camera(camera):
                CameraViewer(camera: camera)
            }
        }
    }
}

extension HomeScreen {
    /// The sheet a chip opens: the Security page's alarm controls (web `SecurityControls`), else a room overview.
    @ViewBuilder
    private func chipSheet(_ kind: HomeConfig.ChipSheet) -> some View {
        if let overview = kind.overview {
            RoomOverviewSheet(kind: overview)
        } else if let caller = callerOverride ?? connection {
            SecuritySystemSheet(caller: caller)
        }
    }
}

/// Sheets presented from Home (web hash modals).
enum HomeSheet: Identifiable, Hashable {
    case chip(HomeConfig.ChipSheet)
    case camera(HomeConfig.Camera)

    var id: String {
        switch self {
        case let .chip(kind): "chip-\(kind.rawValue)"
        case let .camera(camera): "camera-\(camera.entityId)"
        }
    }
}

/// Quiet indicator shown while values come from the disk snapshot instead of the live connection.
struct FreshnessIndicator: View {
    @Environment(EntityStore.self) private var store

    var body: some View {
        if case .snapshot = store.freshness {
            HStack(spacing: HassTokens.Spacing.xs) {
                ArcSpinner(.inline).foregroundStyle(.secondary)
                Text("Updating").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updating from Home Assistant")
        }
    }
}
