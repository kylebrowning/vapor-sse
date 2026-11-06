public import Vapor
public import HTTPTypes

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

extension HTTPField.Name {
    /// The `Last-Event-ID` header an `EventSource` sends when it reconnects.
    public static let lastEventID = HTTPField.Name("Last-Event-ID")!
}

extension Request {
    /// The value of the `Last-Event-ID` header sent by the client on reconnect, if any.
    public var lastEventID: String? {
        headers[.lastEventID]
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
