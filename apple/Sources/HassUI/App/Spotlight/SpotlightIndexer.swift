@preconcurrency import CoreSpotlight
import Foundation
import HassCore
import HassDesign

#if canImport(UIKit)
import UIKit
#endif

/// Puts the app's pages in system search and takes them out (`SpotlightCatalog`).
@MainActor
public protocol SpotlightIndexing: AnyObject {
    /// Replaces the app's items with the catalog's.
    func indexPages(_ entries: [SpotlightEntry])
    /// Removes every item the app indexed.
    func removeAll()
}

/// The `SpotlightIndexing` that does nothing, for tests and journeys that must not touch the system index.
@MainActor
public final class InertSpotlightIndexer: SpotlightIndexing {
    /// Creates an indexer that ignores every call.
    public init() {}
    public func indexPages(_ entries: [SpotlightEntry]) {}
    public func removeAll() {}
}

/// Core Spotlight's default index, filled with one `CSSearchableItem` per ``SpotlightEntry``.
///
/// Items carry the entry's words as `keywords` so a search for "Home Assistant" or "HASS" lists them
/// (`CSSearchableItemAttributeSet.keywords`), and open the app through `CSSearchableItemActionType`
/// (``PushCoordinator/open(spotlightUserInfo:)``). Refreshed whenever a session starts and removed at sign-out.
@MainActor
public final class CoreSpotlightIndexer: SpotlightIndexing {
    private let index: CSSearchableIndex

    /// Creates an indexer.
    /// - Parameter index: The index to fill; the app's default one unless a test supplies its own.
    public init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    public func indexPages(_ entries: [SpotlightEntry]) {
        // One batch replaces the last: delete the domain, then index, so a page dropped from the catalog disappears.
        // Failures are ignored; the next session start indexes again.
        Task { [index] in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightCatalog.domainIdentifier])
            try? await index.indexSearchableItems(entries.map(Self.item))
        }
    }

    public func removeAll() {
        Task { [index] in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightCatalog.domainIdentifier])
        }
    }

    /// The searchable item for an entry.
    /// - Parameter entry: The page.
    static func item(for entry: SpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.displayName = entry.title
        attributes.contentDescription = "\(AppBranding.displayName) · \(entry.summary)"
        attributes.keywords = entry.keywords
        #if canImport(UIKit)
        attributes.thumbnailData = thumbnail(symbol: SymbolMap.symbol(for: entry.mdiIcon))
        #endif
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: SpotlightCatalog.domainIdentifier,
                                attributeSet: attributes)
    }

    #if canImport(UIKit)
    /// An SF Symbol on the app's blue, as the result's icon.
    private static func thumbnail(symbol: String) -> Data? {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 26).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .semibold)
            guard let image = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2))
        }
    }
    #endif
}

/// Hands a page from an App Shortcut to the running app. A shortcut can run before the app finishes launching, so a
/// request made with no handler waits for one.
@MainActor
public enum AppShortcutRouter {
    private static var handler: (@MainActor (PushDestination) -> Void)?
    private static var pending: PushDestination?

    /// Opens `destination` now, or as soon as the app installs its handler.
    public static func route(to destination: PushDestination) {
        if let handler {
            handler(destination)
        } else {
            pending = destination
        }
    }

    /// The app's handler, installed once at launch; runs a request that arrived first.
    public static func install(_ newHandler: @escaping @MainActor (PushDestination) -> Void) {
        handler = newHandler
        if let waiting = pending {
            pending = nil
            newHandler(waiting)
        }
    }

    /// Forgets the handler and any waiting request (tests).
    static func reset() {
        handler = nil
        pending = nil
    }
}
