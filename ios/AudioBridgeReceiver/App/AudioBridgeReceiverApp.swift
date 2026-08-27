import SwiftUI

@main
struct AudioBridgeReceiverApp: App {
    @StateObject private var viewModel = ReceiverViewModel()

    var body: some Scene {
        WindowGroup {
            ReceiverView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

