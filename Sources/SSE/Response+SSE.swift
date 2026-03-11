import Vapor
import Foundation

extension Response {
    /// Creates an SSE streaming response.
    ///
    /// The `handler` closure receives an ``SSEContext`` that you use to send events.
    /// The connection stays open until the handler returns.
    ///
    /// ```swift
    /// app.get("events") { req in
    ///     Response.sse { sse in
    ///         try await sse.send(MyPayload(count: 42))
    ///         try await sse.send(event: "update", data: "done")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - encoder: The `JSONEncoder` used when sending `Encodable` values. Defaults to one that skips escaping slashes.
    ///   - handler: A closure that receives an ``SSEContext`` for sending events.
    public static func sse(
        encoder: JSONEncoder = .sse,
        _ handler: @Sendable @escaping (SSEContext) async throws -> Void
    ) -> Response {
        Response(
            status: .ok,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            ],
            body: .init(managedAsyncStream: { writer in
                let context = SSEContext(writer: writer, encoder: encoder)
                try await handler(context)
            })
        )
    }
}

extension JSONEncoder {
    /// Default encoder for SSE JSON payloads. Produces compact, single-line JSON.
    public static var sse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
