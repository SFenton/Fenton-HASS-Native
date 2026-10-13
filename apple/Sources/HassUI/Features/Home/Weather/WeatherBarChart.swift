import HassCore
import HassDesign
import SwiftUI

/// A small column chart for hourly precipitation chance, accumulation, humidity and cloud cover (web
/// `WeatherPrecipitationTile` / `WeatherHourlyMetricTiles` plots): bars scaled to a "nice" domain, a three-level y axis
/// and a thinned row of hour labels. Decorative for VoiceOver; the tile speaks the series (HIG: Charting data).
struct WeatherBarChart: View {
    /// One value per hour, `nil` where the provider gave none.
    var values: [Double?]
    /// The y-axis top; bars are scaled to it.
    var domain: Double
    /// The y-axis labels from top to bottom.
    var axisLabels: (high: String, middle: String, low: String)
    /// One label per hour; thinned to fit.
    var hourLabels: [String]
    var tint: Color
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 1
    @State private var plotWidth: CGFloat = 0

    private let plotHeight: CGFloat = 76

    var body: some View {
        HStack(alignment: .top, spacing: HassTokens.Spacing.xs) {
            VStack(alignment: .trailing) {
                Text(axisLabels.high)
                Spacer(minLength: 0)
                Text(axisLabels.middle)
                Spacer(minLength: 0)
                Text(axisLabels.low)
            }
            .font(.caption2)
            .foregroundStyle(HassTokens.Ink.onDarkSecondary)
            .frame(height: plotHeight)
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                bars
                hourAxis
            }
        }
        .accessibilityHidden(true)
    }

    private var bars: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(HassTokens.Ink.onDark.opacity(0.14)).frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(values.indices, id: \.self) { index in
                    let percent = WeatherPrecipitationTimeline.scaledPercent(values[index], domain: domain)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(values[index] == nil ? HassTokens.Ink.onDark.opacity(0.18) : tint)
                        .frame(height: values[index] == nil ? 2 : max(percent > 0 ? 2 : 0, plotHeight * percent / 100))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: plotHeight)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(WidthKey.self) { plotWidth = $0 }
    }

    /// Hour labels on a uniform cadence that fits the plot (web `precipitationLabelCadence`).
    private var hourAxis: some View {
        let count = hourLabels.count
        let widest = Double((hourLabels.map(\.count).max() ?? 3)) * 6.6 * Double(min(labelScale, 2.5))
        let cadence = WeatherPrecipitationTimeline.labelCadence(count: count, plotWidth: Double(plotWidth), widestLabelWidth: widest)
        let shown = Set(WeatherPrecipitationTimeline.labelIndices(count: count, cadence: cadence))
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                ZStack(alignment: .leading) {
                    Color.clear
                    if shown.contains(index) {
                        Text(hourLabels[index])
                            .font(.caption2)
                            .fixedSize()
                            .foregroundStyle(HassTokens.Ink.onDarkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}
