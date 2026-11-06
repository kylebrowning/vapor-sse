import Testing
import Vapor
import VaporTesting
import Synchronization
@testable import SSE

/// Runs an SSE response's body and records every chunk it writes, so tests can
/// assert on the exact sequence of writes the SSE layer performs.
///
/// `failAfter` makes the reader throw once it has accepted that many chunks,
/// standing in for a client that disconnects mid-stream.
private func recordWrites(
    of response: Response,
    failAfter limit: Int? = nil
) async throws -> [String] {
    let writes = Mutex<[String]>([])
    try await response.body.withStreamingBytes { span in
        var bytes: [UInt8] = []
        bytes.reserveCapacity(span.count)
        for index in span.indices { bytes.append(span[index]) }
        let count = writes.withLock { writes in
            writes.append(String(decoding: bytes, as: UTF8.self))
            return writes.count
        }
        if let limit, count > limit { throw ClientWentAway() }
    }
    return writes.withLock { $0 }
}

private struct ClientWentAway: Error {}

/// `SSEContext` is `Sendable`, so callers are free to send from several tasks at
/// once (a heartbeat alongside a main event loop, or a fan-in from multiple
/// producers). That is only safe because each event reaches the connection as
/// exactly one write, and writes happen one at a time.
///
/// These tests pin that invariant down. If a future change ever splits an event
/// across multiple writes, concurrent senders could splice one event into the
/// middle of another, and the write-count assertions below start failing.
@Suite("SSE concurrency guarantees")
struct SSEConcurrencyTests {
    @Test func eachSendPerformsExactlyOneWrite() async throws {
        struct Payload: Codable, Sendable { var status: String }

        let response = Response.sse { sse in
            try await sse.send("plain")
            try await sse.send(event: "named", data: "value")
            try await sse.send(Payload(status: "ok"))
            try await sse.send(event: "typed", data: Payload(status: "ok"))
            try await sse.sendComment("keep-alive")
            try await sse.send(ServerSentEvent(id: "1", event: "full", data: "body", retry: 3000))
        }

        let writes = try await recordWrites(of: response)
        #expect(writes == [
            "data: plain\n\n",
            "event: named\ndata: value\n\n",
            "data: {\"status\":\"ok\"}\n\n",
            "event: typed\ndata: {\"status\":\"ok\"}\n\n",
            ": keep-alive\n\n",
            "id: 1\nevent: full\nretry: 3000\ndata: body\n\n",
        ])
    }

    /// Multi-line payloads expand to several `data:` lines. They must still go
    /// out as one write, or a concurrent sender could land between the lines of
    /// a single event.
    @Test func multiLinePayloadIsASingleWrite() async throws {
        let response = Response.sse { sse in
            try await sse.send("first\nsecond\nthird")
        }

        let writes = try await recordWrites(of: response)
        #expect(writes == ["data: first\ndata: second\ndata: third\n\n"])
    }

    /// Large payloads are the most likely candidate for a well-meaning future
    /// refactor to start chunking. They must not be split either.
    @Test func largePayloadIsASingleWrite() async throws {
        let payload = String(repeating: "x", count: 512 * 1024)
        let response = Response.sse { sse in
            try await sse.send(payload)
        }

        let writes = try await recordWrites(of: response)
        #expect(writes.count == 1)
        #expect(writes.first == "data: \(payload)\n\n")
    }

    /// A send returns only once its event has been written, so a handler that
    /// returns has nothing left in flight.
    @Test func sendWaitsForTheWrite() async throws {
        let sent = Mutex(0)
        let response = Response.sse { sse in
            for i in 0..<5 {
                try await sse.send("\(i)")
                sent.withLock { $0 += 1 }
            }
        }

        let writes = try await recordWrites(of: response)
        #expect(writes.count == 5)
        #expect(sent.withLock { $0 } == 5)
    }

    /// When the client goes away, the failed write surfaces as an error from
    /// `send`, which is what unwinds a long-running handler loop.
    @Test func writeFailureFailsTheSendAndEndsTheHandler() async throws {
        let failures = Mutex(0)
        let response = Response.sse { sse in
            for i in 0..<100 {
                do {
                    try await sse.send("\(i)")
                } catch {
                    failures.withLock { $0 += 1 }
                    return
                }
            }
        }

        await #expect(throws: ClientWentAway.self) {
            try await recordWrites(of: response, failAfter: 2)
        }
        #expect(failures.withLock { $0 } == 1)
    }

    /// A write failure also cancels a handler that is busy with something other
    /// than sending, rather than waiting for it to notice on its next send.
    @Test func writeFailureCancelsAnIdleHandler() async throws {
        let response = Response.sse { sse in
            try await sse.send("only")
            try await Task.sleep(for: .seconds(60))
        }

        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ClientWentAway.self) {
            try await recordWrites(of: response, failAfter: 0)
        }
        #expect(clock.now - start < .seconds(5))
    }

    /// Errors thrown by the handler fail the response.
    @Test func handlerErrorPropagates() async throws {
        struct HandlerFailed: Error {}
        let response = Response.sse { sse in
            try await sse.send("before")
            throw HandlerFailed()
        }

        await #expect(throws: HandlerFailed.self) {
            try await recordWrites(of: response)
        }
    }

    /// A context kept around after its handler returned has no connection left.
    /// Sending on it must fail rather than hang.
    @Test func sendAfterStreamEndsThrows() async throws {
        let escaped = Mutex<SSEContext?>(nil)
        let response = Response.sse { sse in
            escaped.withLock { $0 = sse }
            try await sse.send("hello")
        }

        _ = try await recordWrites(of: response)
        let sse = try #require(escaped.withLock { $0 })
        await #expect(throws: SSEStreamClosedError.self) {
            try await sse.send("too late")
        }
    }

    /// Through a real server, each event reaches the client when it is sent,
    /// not when the stream ends. A body that buffered until completion would
    /// look correct to every other test here and be useless for SSE.
    @Test func eventsArriveWhileTheStreamIsOpen() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send("first")
                    try await Task.sleep(for: .seconds(2))
                    try await sse.send("second")
                }
            }

            try await app.testing(.running) { client in
                let clock = ContinuousClock()
                let start = clock.now
                let arrivals = Mutex<[Duration]>([])
                let res = try await client.get("events")
                try await res.body.withStreamingBytes { _ in
                    arrivals.withLock { $0.append(clock.now - start) }
                }
                let times = arrivals.withLock { $0 }
                let first = try #require(times.first)
                let last = try #require(times.last)
                #expect(first < .seconds(1))
                #expect(last >= .seconds(2))
            }
        }
    }

    /// End-to-end check through a real server: many tasks sending at once must
    /// produce intact events, with nothing spliced and nothing dropped.
    @Test func concurrentSendsDoNotInterleave() async throws {
        let eventCount = 200
        let repeats = 50

        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    await withTaskGroup(of: Void.self) { group in
                        for i in 0..<eventCount {
                            group.addTask {
                                // Self-identifying payload: every chunk of a
                                // given event carries the same number, so a
                                // spliced event is detectable.
                                let payload = Array(repeating: "\(i)", count: repeats)
                                    .joined(separator: "-")
                                try? await sse.send(payload)
                            }
                        }
                    }
                }
            }

            try await app.testing(.running) { client in
                let res = try await client.get("events")
                let events = try await res.body.requireString()
                    .components(separatedBy: "\n\n")
                    .filter { !$0.isEmpty }

                #expect(events.count == eventCount)

                var seen = Set<Int>()
                for event in events {
                    guard event.hasPrefix("data: ") else {
                        Issue.record("Event missing data prefix: \(event.prefix(80))")
                        continue
                    }
                    let parts = event.dropFirst("data: ".count).components(separatedBy: "-")
                    let unique = Set(parts)
                    guard unique.count == 1, parts.count == repeats,
                          let value = unique.first.flatMap(Int.init) else {
                        Issue.record("Spliced event: \(event.prefix(80))")
                        continue
                    }
                    seen.insert(value)
                }

                // Every event arrived exactly once and intact.
                #expect(seen.count == eventCount)
            }
        }
    }

    /// The documented heartbeat pattern: a keep-alive task running alongside the
    /// main event stream.
    @Test func heartbeatAlongsideEventsStaysIntact() async throws {
        let count = 100

        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for _ in 0..<count { try? await sse.sendComment("keep-alive") }
                        }
                        group.addTask {
                            for i in 0..<count { try? await sse.send(event: "tick", data: "\(i)") }
                        }
                    }
                }
            }

            try await app.testing(.running) { client in
                let res = try await client.get("events")
                let events = try await res.body.requireString()
                    .components(separatedBy: "\n\n")
                    .filter { !$0.isEmpty }

                let comments = events.filter { $0 == ": keep-alive" }.count
                let ticks = events.filter { $0.hasPrefix("event: tick\ndata: ") }.count

                #expect(comments == count)
                #expect(ticks == count)
                // Nothing else showed up, so nothing was spliced.
                #expect(events.count == comments + ticks)
            }
        }
    }
}
