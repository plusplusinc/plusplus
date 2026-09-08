// Temporary: records the text-layout environment so a cloud run can be compared with a local
// one. Fails on purpose so the values land in the result bundle's failure text.
#if canImport(UIKit) && !os(watchOS)

import Metal
import SwiftUI
import Testing
import UIKit

@Suite("Environment diagnostics")
struct EnvironmentDiagnostics {
    @Test("Record the text layout environment")
    func record() {
        let xxxl = UITraitCollection {
            $0.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: xxxl)
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: xxxl)
        let defaultCaption = UIFont.preferredFont(forTextStyle: .caption1)
        let env = ProcessInfo.processInfo.environment
        let process = ProcessInfo.processInfo

        var lines: [String] = []
        lines.append("os=\(process.operatingSystemVersionString)")
        lines.append("caption@xxxl=\(caption.fontName) pt=\(caption.pointSize)")
        lines.append("  line=\(caption.lineHeight) asc=\(caption.ascender)")
        lines.append("  desc=\(caption.descender) lead=\(caption.leading)")
        lines.append("body@xxxl=\(body.fontName) pt=\(body.pointSize) line=\(body.lineHeight)")
        lines
            .append("caption@default=\(defaultCaption.pointSize) line=\(defaultCaption.lineHeight)")
        lines.append("appContentSize=\(UIApplication.shared.preferredContentSizeCategory.rawValue)")
        lines.append("locale=\(Locale.current.identifier) languages=\(Locale.preferredLanguages)")
        lines.append("boldText=\(UIAccessibility.isBoldTextEnabled)")
        lines.append("reduceMotion=\(UIAccessibility.isReduceMotionEnabled)")
        lines.append("buttonShapes=\(UIAccessibility.buttonShapesEnabled)")
        lines.append("screen=\(UIScreen.main.bounds.size) scale=\(UIScreen.main.scale)")
        lines.append("gpu=\(MTLCreateSystemDefaultDevice()?.name ?? "none")")
        lines.append("simDevice=\(env["SIMULATOR_DEVICE_NAME"] ?? "?")")
        lines.append("runtime=\(env["SIMULATOR_RUNTIME_VERSION"] ?? "?")")
        lines.append("runtimeBuild=\(env["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "?")")
        lines.append("hostEnvKeys=\(interestingKeys(env).joined(separator: ","))")

        Issue.record(Comment(rawValue: "DIAG\n" + lines.joined(separator: "\n")))
    }

    private func interestingKeys(_ env: [String: String]) -> [String] {
        let noise = ["SIMULATOR_", "DYLD", "XPC", "__"]
        return env.keys.sorted().filter { key in !noise.contains { key.hasPrefix($0) } }
    }
}

#endif
