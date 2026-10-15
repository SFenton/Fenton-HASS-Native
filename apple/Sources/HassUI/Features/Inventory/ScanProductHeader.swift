import HassDesign
import SwiftUI

/// The product at the top of Add Item's review step (mockup n6-scan-review): a glyph tile, the name and the scanned
/// barcode.
struct ScanProductHeader: View {
    var name: String
    /// The scanned barcode; `nil` for a typed name.
    var barcode: String?

    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 56

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Image(systemName: barcode == nil ? "square.and.pencil" : "barcode")
                .font(.title2)
                .foregroundStyle(HassTokens.Ink.secondary)
                .frame(width: tileSize, height: tileSize)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "New Item" : name)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                if let barcode {
                    Text("Barcode \(barcode)")
                        .font(.subheadline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, HassTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan.product")
    }
}
