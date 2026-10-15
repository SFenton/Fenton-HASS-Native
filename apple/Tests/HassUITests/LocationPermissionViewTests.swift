import Foundation
@testable import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// The location permission screen: its copy per stage, its actions, and hosted renders of every stage at the
/// default and AX5 text sizes on phone and tablet widths (the device journeys audit it on iPhone, Duo and iPad).
@MainActor
struct LocationPermissionViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tablet = CGSize(width: 820, height: 1180)

    @Test func askingStagesArePreAlertScreensWithOneContinueButton() {
        for stage in [LocationPermission.Stage.notDetermined, .whenInUse] {
            let copy = LocationPermissionCopy(stage: stage)
            #expect(copy.action == .requestPermission)
            #expect(copy.actionTitle == "Continue", "HIG Privacy: never Allow on a pre-alert screen")
            #expect(copy.isPreAlert)
            #expect(copy.showsPoints)
            #expect(copy.footnote?.hasPrefix("Next, iOS asks") == true)
        }
    }

    @Test func statusStagesKeepCloseAndPointToSettings() {
        let always = LocationPermissionCopy(stage: .always)
        #expect(always.action == nil && always.actionTitle == nil && !always.isPreAlert)
        #expect(always.title == "Home and Away Are On")
        for stage in [LocationPermission.Stage.denied, .reducedAccuracy] {
            let copy = LocationPermissionCopy(stage: stage)
            #expect(copy.action == .openSettings)
            #expect(copy.actionTitle == "Open Settings")
            #expect(!copy.isPreAlert && !copy.showsPoints && copy.footnote == nil)
        }
    }

    @Test func titlesAreTitleCaseAndDistinct() {
        let titles = LocationPermission.Stage.allCases.map { LocationPermissionCopy(stage: $0).title }
        #expect(titles == ["Know When You're Home", "Notice When You Leave", "Home and Away Are On", "Location Is Off",
                           "Precise Location Is Off"])
        for stage in LocationPermission.Stage.allCases {
            let message = LocationPermissionCopy(stage: stage).message
            #expect(!message.contains("!") && !message.lowercased().contains("currently"), "Direction G copy rules")
        }
    }

    @Test(arguments: [
        (LocationPermission.notDetermined, "Not Set"),
        (LocationPermission(authorization: .whenInUse), "While Using the App"),
        (LocationPermission(authorization: .always), "Always"),
        (LocationPermission(authorization: .always, isPrecise: false), "Always, Approximate"),
        (LocationPermission(authorization: .whenInUse, isPrecise: false), "While Using the App, Approximate"),
        (LocationPermission(authorization: .denied, isPrecise: false), "Off"),
        (LocationPermission(authorization: .restricted), "Restricted"),
    ])
    func statusValues(permission: LocationPermission, status: String) {
        #expect(LocationPermissionCopy.status(permission) == status)
    }

    @Test func pointsAreNamedAndUseRealSymbols() {
        #expect(LocationPermissionCopy.points.map(\.title) == ["Arrivals and Departures", "Only to Your Server", "Light on Battery"])
        #expect(Set(LocationPermissionCopy.points.map(\.id)).count == 3)
        #if canImport(AppKit)
        let symbols = LocationPermissionCopy.points.map(\.symbol)
            + ["location.circle.fill", "location.fill", "location.slash.fill", "scope"]
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
        #endif
    }

    @Test func actionsReachTheirHandlers() {
        var calls: [String] = []
        let view = LocationPermissionView(
            permission: .notDetermined, onRequestPermission: { calls.append("request") },
            onOpenSettings: { calls.append("settings") }, onClose: { calls.append("close") }
        )
        view.perform(.requestPermission)
        view.perform(.openSettings)
        view.perform(nil)
        #expect(calls == ["request", "settings"])
        // Without a handler, Open Settings goes to the system (a no-op on the macOS host).
        LocationPermissionView(permission: LocationPermission(authorization: .denied), onRequestPermission: {}, onClose: {})
            .perform(.openSettings)
    }

    @Test func everyStageRendersAtEverySize() async {
        for stage in LocationPermission.Stage.allCases {
            let permission = LocationGallery.permission(for: stage)
            #expect(permission.stage == stage)
            for size in [Self.phone, Self.tablet] {
                for typeSize in [DynamicTypeSize.large, .accessibility5] {
                    let hosted = HostedView(
                        LocationPermissionView(permission: permission, onRequestPermission: {}, onClose: {}),
                        size: size, typeSize: typeSize
                    )
                    await hosted.settle()
                    #expect(hosted.fingerprint != 0)
                }
            }
        }
    }

    @Test func galleryWalksThePermissionSteps() async {
        for stage in LocationPermission.Stage.allCases {
            let gallery = SheetHostWindow(LocationGallery(environment: ["FENTON_GALLERY_LOCATION": stage.rawValue]), size: Self.phone)
            gallery.settle()
            #expect(gallery.hasSheet)
        }
        let page = SheetHostWindow(ComponentGallery(page: .location), size: Self.phone)
        page.settle()
        #expect(page.hasSheet)
        #expect(ImageRenderer(content: LocationGallery(environment: [:]).frame(width: 402, height: 874)).cgImage != nil)
    }

    @Test func galleryAnswersLikeTheSystemAlerts() {
        #expect(LocationGallery.answer(to: .notDetermined) == LocationPermission(authorization: .whenInUse))
        #expect(LocationGallery.answer(to: LocationPermission(authorization: .whenInUse)) == LocationPermission(authorization: .always))
        let denied = LocationPermission(authorization: .denied)
        #expect(LocationGallery.answer(to: denied) == denied)
    }
}
