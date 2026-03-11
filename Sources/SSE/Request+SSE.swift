import Vapor
import Foundation

extension Request {
    /// The value of the `Last-Event-ID` header sent by the client on reconnect, if any.
    public var lastEventID: String? {
        headers.first(name: "Last-Event-ID")
    }

    /// Creates an SSE streaming response.
    ///
    /// ```swift
    /// app.get("events") { req in
    ///     req.sse { sse in
    ///         try await sse.send(MyPayload(count: 42))
    ///     }
    /// }
    /// ```
    public func sse(
        encoder: JSONEncoder = .sse,
        _ handler: @Sendable @escaping (SSEContext) async throws -> Void
    ) -> Response {
        .sse(encoder: encoder, handler)
    }
}
