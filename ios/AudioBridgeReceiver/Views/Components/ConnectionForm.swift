import SwiftUI
import UIKit

struct ConnectionForm: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var pairingCode: String
    let isDisabled: Bool
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Windows sender", systemImage: "laptopcomputer")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: 12) {
                LabeledInput(
                    title: "Windows address",
                    text: $host,
                    prompt: "192.168.1.2",
                    keyboardType: .numbersAndPunctuation,
                    textContentType: .URL
                )

                HStack(alignment: .top, spacing: 12) {
                    LabeledInput(
                        title: "Port",
                        text: $port,
                        prompt: "43120",
                        keyboardType: .numberPad,
                        textContentType: nil
                    )
                    LabeledInput(
                        title: "Pairing code",
                        text: $pairingCode,
                        prompt: "000000",
                        keyboardType: .numberPad,
                        textContentType: .oneTimeCode
                    )
                }
            }
            .disabled(isDisabled)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Configuration error: \(validationMessage)")
            }
        }
        .surfaceCard()
    }
}

private struct LabeledInput: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            TextField(prompt, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
