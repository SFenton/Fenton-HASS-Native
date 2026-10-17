import FentonActivityModel
import SwiftUI

/// The three island presentations in a black capsule, for the gallery, the hosted tests and screenshots: the system
/// draws the real island, so this is a stand-in with the real regions inside it.
public struct HomeActivityIslandPreview: View {
    /// Which presentation.
    public enum Kind: String, CaseIterable, Sendable {
        case compact, minimal, expanded
    }

    private let state: HomeActivityState
    private let kind: Kind

    /// Creates the preview.
    public init(state: HomeActivityState, kind: Kind) {
        self.state = state
        self.kind = kind
    }

    public var body: some View {
        Group {
            switch kind {
            case .compact:
                HStack {
                    HomeActivityIsland.CompactLeading(state: state)
                    Spacer(minLength: 90)
                    HomeActivityIsland.CompactTrailing(state: state)
                }
                .padding(.horizontal, 12)
                .frame(width: 250, height: 36)
                .background(Capsule().fill(Color.black))
            case .minimal:
                HomeActivityIsland.Minimal(state: state)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black))
            case .expanded:
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        HomeActivityIsland.ExpandedLeading(state: state)
                        Spacer()
                        HomeActivityIsland.ExpandedTrailing(state: state)
                    }
                    HomeActivityIsland.ExpandedCenter(state: state)
                    HomeActivityIsland.ExpandedBottom(state: state)
                }
                .padding(16)
                .frame(width: 370)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveactivity.island.\(kind.rawValue)")
    }
}
