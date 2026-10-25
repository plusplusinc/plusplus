import os
import QuartzCore
import SwiftUI

// Throwaway: the Start race probe, not for merge.
nonisolated let probeLogger = Logger(subsystem: "probe", category: "start")

nonisolated func probe(_ message: String) {
    let t = String(format: "%.4f", CACurrentMediaTime())
    probeLogger.notice("PROBE t=\(t, privacy: .public) \(message, privacy: .public)")
}

nonisolated func f(_ v: CGFloat) -> String {
    String(format: "%.2f", v)
}

extension ScrollPosition {
    var probeText: String {
        "pos(y:\(y.map { f($0) } ?? "nil") edge:\(edge.map { "\($0)" } ?? "nil") user:\(isPositionedByUser))"
    }
}
