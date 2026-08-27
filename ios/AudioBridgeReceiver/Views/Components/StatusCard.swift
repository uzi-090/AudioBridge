import SwiftUI

struct StatusCard: View {
    let state: ReceiverConnectionState

    private var tint: Color {
        switch state {
        case .playing: AppTheme.success
        case .waitingForAudio, .connecting, .reconnecting: AppTheme.warning
        case .failed: AppTheme.danger
        case .idle: AppTheme.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 58, height: 58)
                Image(systemName: state.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(state.title). \(state.detail)")
    }
}

