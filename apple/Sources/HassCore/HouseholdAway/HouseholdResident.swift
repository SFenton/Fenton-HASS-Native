import Foundation

/// The two people who live in the house (web `src/constants/householdResidents.ts`): Home Assistant users.
///
/// Solo Trip names one as the traveler and the other as the resident at home; the signed-in Home Assistant
/// user maps to a resident so pages can say "You".
extension HouseholdResident {
    // The enum and `name` live in `Bedroom/BedroomConfig.swift`.

    /// The resident's Home Assistant user id.
    public var haUserId: String {
        switch self {
        case .stephen: "64089b5683944c39b4f944c8f76830b0"
        case .steph: "43cb71bbd1cb4860b2a7de4c829020f0"
        }
    }

    /// The other resident.
    public var other: HouseholdResident { self == .stephen ? .steph : .stephen }

    /// The resident signed in as `haUserId`, compared case-insensitively (web `householdResidentForHaUserId`).
    public static func forHaUserId(_ haUserId: String?) -> HouseholdResident? {
        let id = (haUserId ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !id.isEmpty else { return nil }
        return allCases.first { $0.haUserId.lowercased() == id }
    }
}
