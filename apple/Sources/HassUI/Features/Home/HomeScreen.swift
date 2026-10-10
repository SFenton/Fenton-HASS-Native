#if os(iOS)
import HassCore
import HassDesign
import SwiftUI

/// Home (web At a Glance overview). Spec: `.agents/pages/home/spec.md`.
struct HomeScreen: View {
    @Environment(EntityStore.self) private var store
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
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { FreshnessIndicator() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .chip(kind):
                ChipSheet(kind: kind)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case let .camera(camera):
                CameraViewer(camera: camera)
            }
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
                ProgressView().controlSize(.mini)
                Text("Updating").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updating from Home Assistant")
        }
    }
}
#endif
