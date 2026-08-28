import SwiftUI
import UIKit

struct ReceiverView: View {
    @ObservedObject var viewModel: ReceiverViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    StatusCard(state: viewModel.state)
                    ConnectionForm(
                        host: $viewModel.host,
                        port: $viewModel.port,
                        pairingCode: $viewModel.pairingCode,
                        isDisabled: viewModel.state.isConnected || viewModel.state == .connecting,
                        validationMessage: viewModel.validationMessage
                    )
                    bufferSection
                    primaryButton
                    routeCard
                    MetricsGrid(metrics: viewModel.metrics)
                    diagnosticsSection
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 36)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(AppTheme.accent)
        .onAppear {
            updateIdleTimer(for: viewModel.state)
        }
        .onChange(of: viewModel.state) { state in
            updateIdleTimer(for: state)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func updateIdleTimer(for state: ReceiverConnectionState) {
        UIApplication.shared.isIdleTimerDisabled = state.isConnected || state == .connecting
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                Text("AudioBridge")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
            }
            Text("Hear your Windows 11 audio through this iPhone.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playback buffer", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Picker("Playback buffer", selection: Binding(
                get: { viewModel.bufferPreset },
                set: { viewModel.selectBufferPreset($0) }
            )) {
                ForEach(BufferPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.bufferPreset.explanation)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: viewModel.bufferPreset)
        }
        .surfaceCard()
    }

    private var primaryButton: some View {
        Button(action: viewModel.primaryAction) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.primaryButtonSymbol)
                    .accessibilityHidden(true)
                Text(viewModel.primaryButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(AudioBridgePrimaryButtonStyle(isDestructive: viewModel.state.isConnected || viewModel.state == .connecting))
        .accessibilityHint(viewModel.state.isConnected ? "Stops receiving Windows audio." : "Connects to the configured Windows sender.")
    }

    private var routeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "headphones")
                .font(.title2)
                .foregroundStyle(AppTheme.success)
                .frame(width: 44, height: 44)
                .background(AppTheme.success.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio output")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(viewModel.outputRoute)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
            }
            Spacer()
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio output: \(viewModel.outputRoute)")
    }

    private var diagnosticsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.logs.isEmpty {
                    Text("Connection events will appear here.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
        }
        .surfaceCard()
    }
}

private struct AudioBridgePrimaryButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? AppTheme.primaryText : AppTheme.onAccent)
            .background(isDestructive ? AppTheme.surfaceHighlight : (configuration.isPressed ? AppTheme.accentPressed : AppTheme.accent))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
