import SwiftUI

/// Lays its children left to right at their ideal sizes, wrapping onto a new row when the next one doesn't fit, like
/// words in a paragraph (chips under an ingredient, room and option capsules in the vacuum sheet). A child wider than
/// the proposal is narrowed to it so its text wraps.
public struct FlowLayout: Layout {
    /// The gap between children in a row and between rows.
    public var spacing: CGFloat

    /// Creates a flow layout.
    /// - Parameter spacing: The gap between children in a row and between rows.
    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let rightToLeft = subviews.layoutDirection == .rightToLeft
        for row in arrange(width: bounds.width, subviews: subviews) {
            // Every row starts at the leading edge: the left, or the right in a right-to-left layout.
            var x = rightToLeft ? bounds.maxX : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                let width = min(size.width, bounds.width)
                subviews[index].place(at: CGPoint(x: rightToLeft ? x - width : x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
                x += rightToLeft ? -(width + spacing) : width + spacing
            }
            y += row.height + spacing
        }
    }

    /// Groups the children into rows that fit `width`.
    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], itemWidth, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
