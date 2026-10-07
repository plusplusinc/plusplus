import DesignSystem
import SwiftUI

@main
struct PlusPlusApp: App {
    var body: some Scene {
        WindowGroup {
            RoutineScreen()
                .publishesHotReloads()
        }
    }
}
