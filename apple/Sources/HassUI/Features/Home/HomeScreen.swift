import HassCore
import HassDesign
import SwiftUI

/// Home (web At a Glance overview). Spec: `.agents/pages/home/spec.md`.
struct HomeScreen: View {
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.roomServiceCaller) private var callerOverride
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.windowHinge) private var hinge
    @State private var sheet: HomeSheet?
    /// The space Home's content is offered, in window coordinates, for ``HomeColumns``.
    @State private var container: CGRect = .zero

    var body: some View {
        ScrollView {
            content
                // Measure the space offered, not the content: a flexible frame (with `minWidth: 0`) is the same on
                // every pass, so the columns never feed back into the width that decides them
                // (`.agents/design/apple/split-view.md`, Implementation).
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { container = $0 }
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
                    // A room overview navigates to a room's devices; the security system sheet is one page.
                    .hassSheet(.page, height: kind.overview == nil ? .fitted : .full)
            case let .camera(camera):
                CameraViewer(camera: camera)
            }
        }
    }
}

extension HomeScreen {
    /// One column everywhere, except the unfolded Duo in landscape: two halves on the hinge (mockup n1-duo-unfolded).
    @ViewBuilder
    private var content: some View {
        if let columns = HomeColumns.resolve(container: container, isRegularWidth: horizontalSizeClass == .regular, hinge: hinge) {
            // Chips and weather lead; cameras and guests trail. Nothing crosses the hinge, and the hinge band is empty.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                    StatusRail { sheet = .chip($0) }
                    WeatherSummaryCard()
                        // Half a window wide: its hourly row pages by the compact count (nine hours in 400 pt
                        // truncated their labels on the unfolded Duo, 2026-10-15).
                        .environment(\.weatherCardIsNarrow, true)
                        .padding(.horizontal, HassTokens.Spacing.l)
                }
                .frame(width: columns.leadingWidth, alignment: .topLeading)
                Color.clear.frame(width: columns.bandWidth).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                    CameraGrid { sheet = .camera($0) }
                    GuestPresenceSection()
                }
                .padding(.horizontal, HassTokens.Spacing.l)
                .frame(width: columns.trailingWidth, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                StatusRail { sheet = .chip($0) }
                WeatherSummaryCard()
                    .padding(.horizontal, HassTokens.Spacing.l)
                GuestPresenceSection()
                    .padding(.horizontal, HassTokens.Spacing.l)
                CameraGrid { sheet = .camera($0) }
                    .padding(.horizontal, HassTokens.Spacing.l)
            }
        }
    }

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
                ArcSpinner(.inline).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Updating").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updating from Home Assistant")
        }
    }
}
