import SwiftUI

/// A layout that arranges views in a flowing wrap pattern.
/// Used for displaying chips, tags, or buttons that should wrap to multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        // Use screen width as fallback instead of .infinity to prevent NaN propagation
        let screenWidth = UIScreen.main.bounds.width
        let maxWidth = proposal.width ?? screenWidth

        // Guard against invalid widths
        guard maxWidth.isFinite, maxWidth > 0 else {
            return (CGSize(width: screenWidth, height: 0), [])
        }

        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Guard against invalid subview sizes
            guard size.width.isFinite, size.height.isFinite else { continue }

            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        // Calculate actual width used instead of returning maxWidth
        maxRowWidth = max(maxRowWidth, x - spacing)
        let actualWidth = min(maxRowWidth, maxWidth)

        return (CGSize(width: actualWidth, height: y + rowHeight), positions)
    }
}
