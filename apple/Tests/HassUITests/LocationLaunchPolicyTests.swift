import Foundation
@testable import HassUI
import Testing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "location-policy-tests-\(UUID().uuidString)")!
}

struct LocationLaunchPolicyTests {
    @Test func phonesOnlyAndNotInJourneys() {
        #expect(LocationLaunchPolicy.isEnabled(environment: [:], isPresenceDevice: true))
        #expect(!LocationLaunchPolicy.isEnabled(environment: [:], isPresenceDevice: false), "never on iPad")
        #expect(!LocationLaunchPolicy.isEnabled(environment: ["FENTON_LOCATION": "1"], isPresenceDevice: false))
        for key in ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"] {
            #expect(!LocationLaunchPolicy.isEnabled(environment: [key: "1"], isPresenceDevice: true))
            #expect(LocationLaunchPolicy.isEnabled(environment: [key: "1", "FENTON_LOCATION": "1"], isPresenceDevice: true))
        }
    }

    @Test func reportingIsArmedPerInstall() {
        let defaults = freshDefaults()
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults))
        #expect(LocationLaunchPolicy.isReportingArmed(environment: ["FENTON_LOCATION_REPORT": "1"], defaults: defaults))
        #expect(LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults), "persists")
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: ["FENTON_LOCATION_REPORT": "0"], defaults: defaults))
        #expect(!LocationLaunchPolicy.isReportingArmed(environment: [:], defaults: defaults))
    }
}
