import SwiftUI
import AppKit

@main
struct TranslatorApp: App {
    @StateObject private var viewModel = TranslatorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
