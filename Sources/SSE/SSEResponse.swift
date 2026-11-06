import Vapor

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Thrown by ``SSEContext`` sends once the stream they belong to has ended.
///
/// The usual cause is keeping a reference to the context and sending after the
/// handler has returned. The stream ends when the handler does, so there is no
/// connection left to write to.
public struct SSEStreamClosedError: Error, Sendable, Equatable {
    public init() {}
}

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
/// Vapor lends the response body writer to a single task for the life of the
/// stream, so sends don't touch the connection directly. Each one hands its
/// serialized event to that task and waits until the event has been written.
/// Events are written one at a time and each is a single write, so two tasks
/// sending at the same time cannot splice one event into the middle of another.
///
/// - Important: What concurrent sending does *not* give you is ordering. Two
///   tasks racing to send have no defined order between them, so if you are
///   stamping `id` values for `Last-Event-ID` resume, send those from a single
///   task. Sequential `await`s from one task are always ordered, because each
///   send completes before the next begins.
public final class SSEContext: Sendable {
    /// A serialized event waiting to be written, and the send waiting on it.
    struct Outgoing: Sendable {
        let text: String
        let written: CheckedContinuation<Void, any Error>
    }

    private let outbox: AsyncStream<Outgoing>.Continuation
    private let encoder: JSONEncoder

    init(outbox: AsyncStream<Outgoing>.Continuation, encoder: JSONEncoder) {
        self.outbox = outbox
        self.encoder = encoder
    }

    /// Runs `handler` against a fresh context, writing everything it sends to `writer`.
    ///
    /// The handler runs in a child task while this task keeps the writer, which
    /// is borrowed and can't be captured by another task. Returns once the
    /// handler has finished and every event it sent has been written. A handler
    /// error is rethrown. A write error is rethrown too, after the handler has
    /// been cancelled and has unwound.
    nonisolated(nonsending) static func run(
        writer: borrowing any HTTPBodyWriter & ~Escapable,
        encoder: JSONEncoder,
        _ handler: @Sendable @escaping (SSEContext) async throws -> Void
    ) async throws {
        let (events, outbox) = AsyncStream<Outgoing>.makeStream()
        let context = SSEContext(outbox: outbox, encoder: encoder)

        // `async let` rather than a task group: a group's body is a closure, and
        // capturing the borrowed writer in a closure would consume it. Leaving
        // this scope by throwing cancels the handler and waits for it.
        async let handlerDone: Void = {
            // Ending the outbox ends the write loop below, once it has drained
            // what was already sent.
            defer { outbox.finish() }
            try await handler(context)
        }()

        for await event in events {
            do {
                try await writer.write(event.text)
                event.written.resume()
            } catch {
                event.written.resume(throwing: error)
                // The connection is gone. Close the outbox so later sends fail
                // straight away, then fail anything already queued, so no send
                // is left waiting on a write that will never happen.
                outbox.finish()
                for await queued in events {
                    queued.written.resume(throwing: error)
                }
                throw error
            }
        }

        try await handlerDone
    }

    /// Sends a ``ServerSentEvent`` to the client.
    ///
    /// Returns once the event has been written to the connection.
    ///
    /// - Throws: The write error if the client has gone away, or
    ///   ``SSEStreamClosedError`` if the stream has already ended.
    public func send(_ event: ServerSentEvent) async throws {
        let text = event.serialize()
        try await withCheckedThrowingContinuation { (written: CheckedContinuation<Void, any Error>) in
            if case .terminated = outbox.yield(Outgoing(text: text, written: written)) {
                written.resume(throwing: SSEStreamClosedError())
            }
        }
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
