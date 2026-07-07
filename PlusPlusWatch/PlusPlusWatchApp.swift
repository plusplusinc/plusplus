import SwiftUI

@main
struct PlusPlusWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
