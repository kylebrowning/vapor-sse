import Vapor
import NIOCore
import Foundation

/// A handle for an active SSE connection. Use it to send events to the client.
///
/// ## Concurrency
///
/// `SSEContext` is `Sendable`, and sending from several tasks at once is safe.
/// A common case is a keep-alive heartbeat running alongside the main event
/// stream:
///
/// ```swift
/// req.sse { sse in
///     await withTaskGroup(of: Void.self) { group in
///         group.addTask { for await event in stream { try? await sse.send(event) } }
///         group.addTask { while true { try? await sse.sendComment("keep-alive") } }
///     }
/// }
/// ```
///
/// Each event is written as a single buffer, which Vapor dispatches onto the
/// connection's event loop as one unit, so events are always delivered whole.
/// Two tasks sending at the same time cannot splice one event into the middle
/// of another.
///
/// - Important: What concurrent sending does *not* give you is ordering. Two
///   tasks racing to send have no defined order between them, so if you are
///   stamping `id` values for `Last-Event-ID` resume, send those from a single
///   task. Sequential `await`s from one task are always ordered, because each
///   send completes before the next begins.
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
