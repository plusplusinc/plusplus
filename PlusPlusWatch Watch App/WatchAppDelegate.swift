#if canImport(Session)
import Foundation
import Health
import HealthKit
import OSLog
import Session
import WatchKit
import WorkoutStore

/// The app's one `WatchWorkout`, and the system's ways in: Start on the phone brings the app
/// up through `handle(_:)`. The one file that imports HealthKit, for the configuration that
/// call takes.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let workout = WatchWorkout(
        mirror: .live,
        saved: try? Data(contentsOf: WatchAppDelegate.savedURL),
        write: WatchAppDelegate.save,
        haptic: WatchAppDelegate.play,
    )

    func applicationDidFinishLaunching() {
        workout.listen()
        Task { await workout.recover() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await workout.start() }
    }

    /// The workout as the Watch last held it, so a relaunch mid-workout comes back on the same
    /// set with its unconfirmed taps.
    private static var savedURL: URL {
        URL.applicationSupportDirectory.appending(path: "LinkedWorkout.json")
    }

    private static func save(_ data: Data?) {
        let url = savedURL
        do {
            if let data {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            Logger.watchApp.error("Saving the workout failed: \(error)")
        }
    }

    /// First guesses at each one's feel, for the maintainer to tune on the wrist.
    private static func play(_ haptic: WatchHaptic) {
        let type: WKHapticType = switch haptic {
        case .setLogged: .click
        case .restEnded: .notification
        case .startInEnded: .start
        case .setRanOut, .finished: .success
        }
        WKInterfaceDevice.current().play(type)
    }
}

extension Logger {
    static let watchApp = Logger(subsystem: "com.plusplusinc.plusplus", category: "watch-app")
}
#endif
