#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Views in a state the galleries don't reach on their own: a program row on its own, the remote's glass tile in each
/// of its semantics, and the live Security and Chores pages inside the environment the app gives them.
@MainActor
@Suite(.serialized)
struct ViewStatesTests {
    static let phone = CGSize(width: 402, height: 874)

    func connection() -> HassConnection {
        HassConnection(server: AppSessionTests.server, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
    }

    func session() -> AppSession {
        AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "states-\(UUID()).json")))
    }

    // MARK: Remote tile

    @Test func theRemoteTileReadsAndActsAccordingToItsSemantics() async throws {
        var fired: [String] = []
        func tile(_ semantics: ControlSemantics, disabled: Bool = false, label: String) -> some View {
            RemoteGlassTile(title: label, subtitle: "Sub", symbol: "tv", tint: .blue, isActive: true, isDisabled: disabled,
                            semantics: semantics) { fired.append(label) }
        }
        let cases: [(ControlSemantics, Bool, String)] = [
            (.toggle(isOn: true), false, "Toggle"), (.selection(isSelected: true), false, "Chosen"),
            (.selection(isSelected: false), false, "Other"), (.state, false, "State"), (.command, false, "Command"),
            (.command, true, "Unplugged"),
        ]
        let hosted = HostedWindow(
            VStack { ForEach(Array(cases.enumerated()), id: \.offset) { _, item in tile(item.0, disabled: item.1, label: item.2).frame(width: 160, height: 90) } },
            size: CGSize(width: 220, height: 640)
        )
        defer { hosted.close() }
        await hosted.settle(0.6)
        #expect(try #require(hosted.snapshot()).distinctColors > 3)
        let header = HostedWindow(RemoteSectionHeader(title: "Volume").padding(), size: CGSize(width: 240, height: 80))
        defer { header.close() }
        await header.settle(0.3)
        #expect(try #require(header.snapshot()).distinctColors >= 2)
    }

    // MARK: Program row

    @Test func aProgramRowOffersItsScheduleAndASwitchForItsEnabledState() async throws {
        let store = EntityStore()
        store.replaceAll(HomePageFixtures.states, freshness: .live)
        let recorder = RecordingCaller()
        let controller = SprinklerController(config: SprinklersConfig.backyard, store: store, caller: recorder)
        let program = try #require(controller.program(0))
        let row = ProgramRow(controller: controller, index: 0, zoneName: "Bushes", program: program, format: SprinklerFormat())
        let driver = AXWindow(NavigationStack { List { row } }, size: CGSize(width: 402, height: 300))
        defer { driver.close() }
        let nodes = await driver.wait { $0.contains { $0.identifier == "sprinkler.program.0.enabled" } }
        let link = try #require(nodes.first { $0.identifier == "sprinkler.program.0" })
        #expect(link.isEnabled == program.available)
        #expect(link.spoken.contains(SprinklerFormat().programName(zone: "Bushes")), "the row is named for its zone: \(link.spoken)")
        let toggle = try #require(nodes.first { $0.identifier == "sprinkler.program.0.enabled" })
        #expect(toggle.value == (program.enabled ? "1" : "0"), "the switch shows the program's state")
    }

    // MARK: Live pages

    @Test func theSecurityPageDrawsInsideTheAppsEnvironmentAndSendsOnlyWhenConnected() async throws {
        let connection = connection()
        let hosted = HostedWindow(NavigationStack { SecurityScreen() }.environment(connection).environment(connection.store),
                                  size: Self.phone)
        defer { hosted.close() }
        await hosted.settle(1.0)
        #expect(try #require(hosted.snapshot()).distinctColors > 3)
        #expect(SecurityScreen.canSend(.connected(version: "2026.10.1")) && SecurityScreen.canSend(.connecting))
        #expect(!SecurityScreen.canSend(.disconnected) && !SecurityScreen.canSend(.rejected))
    }

    @Test func theChoresPageDrawsInsideItsModelHost() async throws {
        let connection = connection()
        let hosted = HostedWindow(
            NavigationStack { ChoresModelHost { ChoresContent() } }
                .environment(connection).environment(connection.store).environment(session()),
            size: Self.phone
        )
        defer { hosted.close() }
        await hosted.settle(1.2)
        #expect(try #require(hosted.snapshot()).distinctColors > 3)
    }
}
#endif
