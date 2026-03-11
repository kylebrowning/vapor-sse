import Vapor
import NIOCore
import Foundation

/// A handle for an active SSE connection. Use it to send events to the client.
public final class SSEContext: Sendable {
    private let writer: AsyncBodyStreamWriter
    private let encoder: JSONEncoder

    init(writer: AsyncBodyStreamWriter, encoder: JSONEncoder) {
        self.writer = writer
        self.encoder = encoder
    }

    /// Sends a ``ServerSentEvent`` to the client.
    public func send(_ event: ServerSentEvent) async throws {
        let serialized = event.serialize()
        var buffer = ByteBufferAllocator().buffer(capacity: serialized.utf8.count)
        buffer.writeString(serialized)
        try await writer.writeBuffer(buffer)
    }

    /// Sends a data-only event with a raw string.
    public func send(_ data: String) async throws {
        try await send(ServerSentEvent(data: data))
    }

    /// Sends a data-only event with an `Encodable` value as JSON.
    public func send<T: Encodable & Sendable>(_ value: T) async throws {
        let json = try encoder.encode(value)
        try await send(ServerSentEvent(data: String(decoding: json, as: UTF8.self)))
    }

    /// Sends a named event with a raw string.
    public func send(event: String, data: String) async throws {
        try await send(ServerSentEvent(event: event, data: data))
    }

    /// Sends a named event with an `Encodable` value as JSON.
    public func send<T: Encodable & Sendable>(event: String, data value: T) async throws {
        let json = try encoder.encode(value)
        try await send(ServerSentEvent(event: event, data: String(decoding: json, as: UTF8.self)))
    }

    /// Sends a comment line. Useful as a keep-alive.
    public func sendComment(_ comment: String) async throws {
        try await send(ServerSentEvent(comment: comment))
    }
}
