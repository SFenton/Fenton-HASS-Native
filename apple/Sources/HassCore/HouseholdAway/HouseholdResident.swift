import Foundation

/// The two people who live in the house (web `src/constants/householdResidents.ts`): Home Assistant users.
///
/// Solo Trip names one as the traveler and the other as the resident at home; the signed-in Home Assistant
/// user maps to a resident so pages can say "You".
extension HouseholdResident {
    // The enum and `name` live in `Bedroom/BedroomConfig.swift`, `haUserId` in `Rooms/RoomModel.swift`.

    /// The other resident.
    public var other: HouseholdResident { self == .stephen ? .steph : .stephen }

    /// The resident signed in as `haUserId`, compared case-insensitively (web `householdResidentForHaUserId`).
    public static func forHaUserId(_ haUserId: String?) -> HouseholdResident? {
        let id = (haUserId ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !id.isEmpty else { return nil }
        return allCases.first { $0.haUserId.lowercased() == id }
    }
}
