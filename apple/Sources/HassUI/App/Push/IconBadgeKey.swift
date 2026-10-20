/// Re-runs the icon badge task when the count or the setting changes.
struct IconBadgeKey: Equatable {
    var count: Int
    var enabled: Bool
}
