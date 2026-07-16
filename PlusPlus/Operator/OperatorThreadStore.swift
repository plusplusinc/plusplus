import Foundation
import PlusPlusKit

/// One message in the Operator thread — the persisted, renderable unit.
/// Cards are messages too (previews, receipts, option prompts), so the
/// thread file IS the transcript the user scrolls.
struct OperatorMessage: Identifiable, Codable, Equatable {
    enum Kind: Codable, Equatable {
        case user(String)
        case reply(String)
        case preview(PreviewPayload)
        case receipt(ReceiptPayload)
        case options(OptionsPayload)
        /// A quiet system line in Operator's voice (errors, notices).
        case notice(String)
    }

    /// A staged change awaiting Apply/Cancel. Carries the SPEC — Apply
    /// re-resolves at tap time; nothing here references live models.
    struct PreviewPayload: Codable, Equatable {
        enum State: String, Codable {
            case pending, applied, cancelled
        }
        let spec: ChangeSpec
        let headline: String
        let lines: [String]
        var state: State = .pending
    }

    /// An applied change. `undoable` reflects depth-1 undo: only the
    /// LATEST applied change can undo, and only within this launch.
    struct ReceiptPayload: Codable, Equatable {
        let summary: String
        let destinations: [OperatorDestination]
        var undoable: Bool
        var undone: Bool = false
    }

    /// ask_user's tappable choices; `selection` records the answer once
    /// tapped (the tap also becomes the next user turn).
    struct OptionsPayload: Codable, Equatable {
        let question: String
        let options: [String]
        let allowMultiple: Bool
        var selection: [String]? = nil
    }

    let id: UUID
    let date: Date
    var kind: Kind

    init(id: UUID = UUID(), date: Date = Date(), kind: Kind) {
        self.id = id
        self.date = date
        self.kind = kind
    }
}

/// The rolling thread on disk: one JSON file in Application Support,
/// atomic writes, capped at `OperatorThreadPolicy.storeCap` (oldest
/// trimmed on save). Deliberately NOT SwiftData (no migration surface,
/// no interchange census entanglement) and NOT backup-excluded — the
/// conversation is user-visible state, not a rebuildable cache.
struct OperatorThreadStore {
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Operator", isDirectory: true)
        url = base.appendingPathComponent("thread.json")
    }

    /// A corrupt or missing file reads as an empty thread — never a
    /// crash, never an error the user has to see.
    func load() -> [OperatorMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([OperatorMessage].self, from: data)) ?? []
    }

    func save(_ messages: [OperatorMessage]) {
        let capped = Array(messages.suffix(OperatorThreadPolicy.storeCap))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(capped)
            try data.write(to: url, options: .atomic)
        } catch {
            // A failed save loses nothing but scroll-back history; the
            // in-memory thread stays intact and the next save retries.
        }
    }
}
