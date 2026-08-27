import SwiftUI

struct MetricsGrid: View {
    let metrics: ReceiverMetrics

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(title: "Estimated delay", value: "\(metrics.estimatedLatencyMilliseconds)", unit: "ms")
            MetricTile(title: "Network jitter", value: String(format: "%.1f", metrics.jitterMilliseconds), unit: "ms")
            MetricTile(title: "Packet rate", value: "\(metrics.packetsPerSecond)", unit: "/s")
            MetricTile(title: "Dropped", value: "\(metrics.packetsDropped)", unit: "packets")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .minimumScaleFactor(0.75)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(14)
        .background(AppTheme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

