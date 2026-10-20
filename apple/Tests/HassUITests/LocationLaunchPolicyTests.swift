import Foundation
@testable import HassUI
import Testing

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
}
