import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import SwiftUI
import Testing

/// The Account sheet's Location section: the warning an armed toggle shows when nothing can be sent, and hosted
/// renders on phone widths at the default and AX5 text sizes (the journeys audit it on iPhone and Duo, and check it is
/// absent on iPad).
@MainActor
struct LocationAccountSectionTests {
    private func coordinator(_ permission: LocationPermission, armed: Bool) -> LocationCoordinator {
        let mobileApp = MobileAppCoordinator(device: {
            MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                            deviceID: "v", apnsEnvironment: .sandbox)
        }, store: InMemoryMobileAppRegistrationStore(), transport: StubHTTPTransport([]))
        return LocationCoordinator(platform: FakeLocationPlatform(permission), mobileApp: mobileApp, isReportingArmed: armed,
                                   transport: StubHTTPTransport([]),
                                   defaults: UserDefaults(suiteName: "location-account-\(UUID().uuidString)")!)
    }

    @Test func anArmedToggleWarnsOnlyWhenNothingCanBeSent() {
        for stage in LocationPermission.Stage.allCases {
            #expect(LocationAccountSection.warning(armed: false, stage: stage) == nil, "off never warns")
        }
        #expect(LocationAccountSection.warning(armed: true, stage: .always) == nil)
        #expect(LocationAccountSection.warning(armed: true, stage: .whenInUse) == nil)
        for stage in [LocationPermission.Stage.notDetermined, .denied, .reducedAccuracy] {
            let warning = LocationAccountSection.warning(armed: true, stage: stage)
            #expect(warning?.isEmpty == false)
            #expect(warning?.hasSuffix(".") == true)
        }
        #expect(LocationAccountSection.footer.contains("added to a person"))
    }

    @Test func rendersArmedAndOffAtEverySize() async {
        for (permission, armed) in [(LocationPermission(authorization: .always), true),
                                    (LocationPermission(authorization: .denied), true),
                                    (LocationPermission.notDetermined, false)] {
            let location = coordinator(permission, armed: armed)
            for typeSize in [DynamicTypeSize.large, .accessibility5] {
                let hosted = HostedView(
                    List { LocationAccountSection(location: location, showsPermission: .constant(false)) }.environment(\.tileSurface, .sheet),
                    size: LocationPermissionViewTests.phone, typeSize: typeSize
                )
                await hosted.settle()
                #expect(hosted.fingerprint != 0)
            }
        }
    }

    @Test func theProfileTabShowsTheSectionOnlyWithACoordinator() async {
        // A phone's session has a coordinator; an iPad's has none, so its Profile tab has no Location section.
        for location in [coordinator(.notDetermined, armed: false), nil] {
            let hosted = HostedView(YourSummarySheet(opening: .profile).environment(ShellNavigator()).environment(location),
                                    size: LocationPermissionViewTests.phone, typeSize: .large)
            await hosted.settle()
            #expect(hosted.fingerprint != 0)
        }
    }

    @Test func thePermissionSheetFollowsTheCoordinator() async {
        let location = coordinator(LocationPermission(authorization: .whenInUse), armed: false)
        var closed = false
        let hosted = HostedView(LocationPermissionSheet(location: location) { closed = true },
                                size: LocationPermissionViewTests.phone, typeSize: .large)
        await hosted.settle()
        #expect(hosted.fingerprint != 0)
        location.requestPermission()
        #expect(location.hasAskedForAlways, "Continue on While Using asks for Always once")
        #expect(!closed)
    }
}
