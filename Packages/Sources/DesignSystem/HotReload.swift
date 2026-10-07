import SwiftUI

// Hot reload with InjectionNext (see the README). InjectionNext swaps recompiled functions into
// the running app and posts a notification; nothing redraws on its own. The root publishes a
// reload count, and each view that declares `@ObserveHotReload` re-runs its body when the count
// changes, keeping its identity and state. All of it compiles out of Release. This file holds no
// views, so injecting a view's file never replaces the counter or its static storage.

/// Redraws the view that declares it after each hot reload:
/// `@ObserveHotReload private var hotReload`. SwiftUI re-runs a body only when that view's
/// inputs change, so a view without this keeps showing its old body.
@propertyWrapper
public struct ObserveHotReload: DynamicProperty {
    #if DEBUG
    @Environment(\.injectionCount) private var count
    #endif

    public init() { }

    public var wrappedValue: Void {
        ()
    }
}

extension View {
    /// Publishes hot reloads to the hierarchy. Apply once, at the root.
    public func publishesHotReloads() -> some View {
        #if DEBUG
        modifier(PublishHotReloads())
        #else
        self
        #endif
    }

    #if DEBUG
    /// Ends a hot-reloadable body. A body's type is fixed when the app launches, and an edit that
    /// adds or removes a modifier changes it, which crashes SwiftUI; erasing the body to
    /// `AnyView` keeps its type the same across reloads.
    public func hotReloadable() -> AnyView {
        AnyView(self)
    }
    #else
    public func hotReloadable() -> Self {
        self
    }
    #endif
}

extension EnvironmentValues {
    @Entry var injectionCount = 0
}

#if DEBUG
@Observable
final class InjectionCounter {
    static let shared = InjectionCounter()
    private(set) var count = 0

    private init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"), object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }
}

private struct PublishHotReloads: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.injectionCount, InjectionCounter.shared.count)
    }
}
#endif
