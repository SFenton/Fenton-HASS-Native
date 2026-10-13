import HassCore
import HassDesign
import SwiftUI

/// A room pushed from an overview sheet: the group's title, its live summary and its tiles (web room detail inside
/// `ModalSheet`, title `group.title`, subtitle `roomDetailSubtitle`).
struct RoomGroupDetailPage: View {
    var kind: RoomOverviewKind
    var group: RoomGroup
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.roomServiceCaller) private var callerOverride
    /// Home Assistant's message for a light change it rejected.
    @State private var failure = ""
    @State private var showsFailure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                Text(RoomOverview.detailSubtitle(kind, group, read: read))
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("overview.detail.subtitle")
                RoomGroupDetail(kind: kind, group: group, read: read, send: send)
            }
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(RoomOverview.detailTitle(kind, group))
        .inlineNavigationTitle()
        .accessibilityIdentifier("overview.detail.\(group.room)")
        .alert("Couldn't Change the Light", isPresented: $showsFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure)
        }
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }

    private func send(_ command: LightControl.Command) {
        guard let caller = callerOverride ?? connection else { return }
        Task {
            do {
                try await caller.callService(command.domain, command.service, data: command.serviceData)
            } catch {
                failure = ServiceErrorText.message(for: error, fallback: "Home Assistant didn't accept the change. Try again.")
                showsFailure = true
            }
        }
    }
}
