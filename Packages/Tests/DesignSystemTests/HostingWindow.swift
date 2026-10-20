// Runs only where UIKit exists, as the suites that use it do.
#if canImport(UIKit) && !os(watchOS)

import UIKit

extension UIWindow {
    /// A key window of a phone's size showing `host` at the text size `category`, for the
    /// suites that need a field to take focus, a size to change live, or every layout pass seen.
    ///
    /// The package's tests run with no host app, so there is no scene for
    /// `init(windowScene:)`; this is the one place that uses the deprecated `init(frame:)`, which
    /// still lays out, takes traits, and focuses a field.
    static func sceneless(
        hosting host: UIViewController,
        at category: UIContentSizeCategory,
    ) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.traitOverrides.preferredContentSizeCategory = category
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    /// Lets every update the last step started reach the layout.
    func settle() {
        for _ in 0 ..< 10 {
            layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: .now)
        }
    }
}

#endif
