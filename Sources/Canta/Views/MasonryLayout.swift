import SwiftUI

/// A Pinterest-style masonry that balances cards into the shortest column.
struct MasonryLayout: Layout {
    var minColumnWidth: CGFloat = 240
    var maxColumns: Int = 5
    var columnSpacing: CGFloat = 20
    var rowSpacing: CGFloat = 28

    private func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 800 }
        return width
    }

    private func columnCount(for width: CGFloat) -> Int {
        let width = resolvedWidth(width)
        let count = Int((width + columnSpacing) / (minColumnWidth + columnSpacing))
        return max(2, min(maxColumns, count))
    }

    private func columnWidth(for width: CGFloat, columns: Int) -> CGFloat {
        (resolvedWidth(width) - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(proposal.width ?? 800)
        let columns = columnCount(for: width)
        let cardWidth = columnWidth(for: width, columns: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            heights[target] += size.height + rowSpacing
        }

        let tallest = (heights.max() ?? 0) - (subviews.isEmpty ? 0 : rowSpacing)
        return CGSize(width: width, height: max(0, tallest))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = resolvedWidth(bounds.width)
        let columns = columnCount(for: width)
        let cardWidth = columnWidth(for: width, columns: columns)
        var heights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let origin = CGPoint(
                x: bounds.minX + CGFloat(target) * (cardWidth + columnSpacing),
                y: bounds.minY + heights[target]
            )
            subview.place(at: origin, proposal: ProposedViewSize(width: cardWidth, height: size.height))
            heights[target] += size.height + rowSpacing
        }
    }
}