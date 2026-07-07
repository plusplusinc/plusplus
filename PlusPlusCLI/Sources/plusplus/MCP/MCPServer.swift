import Foundation
import PlusPlusKit

/// A minimal MCP (Model Context Protocol) server over stdio: newline-
/// delimited JSON-RPC 2.0, tools capability only. Exposes a routine repo
/// to agents — `plusplus mcp --repo ~/routines` and point your client at
/// it (docs/AGENTS.md in the main repo).
///
/// The protocol layer is deliberately hand-rolled: it's ~100 lines, the
/// dependency-free build matters (Linux CI, future static binaries), and
/// the tool surface is small and stable.
struct MCPServer {
    let repoRoot: String

    static let serverName = "plusplus"
    static let protocolVersion = "2025-06-18"

    // MARK: - Wire loop

    /// Blocks reading newline-delimited JSON-RPC from stdin until EOF.
    func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handle(line: line) {
                print(response)
                fflush(nil) // flush all streams; `stdout` itself isn't concurrency-safe to name in Swift 6
            }
        }
    }

    /// One request in, one response out. Nil for notifications (no id) —
    /// JSON-RPC forbids replying to them. Split from `serve()` so tests
    /// can drive the server without a process.
    func handle(line: String) -> String? {
        guard
            let data = line.data(using: .utf8),
            let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return encodeResponse(id: nil, error: (-32700, "Parse error"))
        }

        let id = message["id"]
        let isNotification = id == nil
        guard let method = message["method"] as? String else {
            return isNotification ? nil : encodeResponse(id: id, error: (-32600, "Invalid request"))
        }
        let params = message["params"] as? [String: Any] ?? [:]

        let result: [String: Any]?
        switch method {
        case "initialize":
            result = [
                "protocolVersion": Self.protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.serverName, "version": "\(Interchange.schemaVersion)"],
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": MCPToolbox.definitions]
        case "tools/call":
            guard let name = params["name"] as? String else {
                return isNotification ? nil : encodeResponse(id: id, error: (-32602, "Missing tool name"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            result = callTool(named: name, arguments: arguments)
        case _ where method.hasPrefix("notifications/"):
            return nil
        default:
            return isNotification ? nil : encodeResponse(id: id, error: (-32601, "Method not found: \(method)"))
        }

        return isNotification ? nil : encodeResponse(id: id, result: result ?? [:])
    }

    // MARK: - Tools

    private func callTool(named name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            let text = try MCPToolbox.call(name: name, arguments: arguments, repoRoot: repoRoot)
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            return ["content": [["type": "text", "text": "error: \(error)"]], "isError": true]
        }
    }

    // MARK: - Encoding

    private func encodeResponse(id: Any?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func encodeResponse(id: Any?, error: (code: Int, message: String)) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": error.code, "message": error.message]])
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
