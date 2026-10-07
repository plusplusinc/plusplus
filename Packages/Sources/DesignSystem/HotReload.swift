import SwiftUI

#if DEBUG
/// Counts InjectionNext's hot reloads. InjectionNext swaps recompiled functions into the running
/// app and then posts this notification; nothing redraws on its own. Lives in its own file so
/// injecting a view's file never replaces this class or its static storage.
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
#endif

extension EnvironmentValues {
    @Entry var injectionCount = 0
}

extension View {
    /// Publishes hot reloads to the hierarchy. Apply once, at the root. Compiled out of Release.
    public func publishesHotReloads() -> some View {
        #if DEBUG
        modifier(PublishHotReloads())
        #else
        self
        #endif
    }
}

/// Redraws the view that declares it after each hot reload, keeping its identity and state:
/// `@ObserveHotReload private var hotReload`. SwiftUI re-runs a body only when that view's
/// inputs change, so a view without this keeps showing its old body until something else
/// changes. Compiled out of Release.
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
    #if DEBUG
    /// Ends a hot-reloadable body. A body's type is fixed when the app launches, and an edit that
    /// adds or removes a modifier changes it, which crashes SwiftUI; erasing the body to
    /// `AnyView` keeps its type the same across reloads. Debug only: Release keeps static types.
    public func hotReloadable() -> AnyView {
        AnyView(self)
    }
    #else
    public func hotReloadable() -> Self {
        self
    }
    #endif
}

#if DEBUG
private struct PublishHotReloads: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.injectionCount, InjectionCounter.shared.count)
    }
}
#endif
