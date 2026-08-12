import Testing
import Vapor
import VaporTesting
import NIOCore
import NIOConcurrencyHelpers
@testable import SSE

/// Records every buffer handed to the body stream, so tests can assert on the
/// exact sequence of writes the SSE layer performs.
private final class RecordingWriter: AsyncBodyStreamWriter, Sendable {
    private let storage = NIOLockedValueBox<[String]>([])

    var writes: [String] {
        storage.withLockedValue { $0 }
    }

    func write(_ result: BodyStreamResult) async throws {
        guard case .buffer(let buffer) = result else { return }
        storage.withLockedValue { $0.append(String(buffer: buffer)) }
    }
}

/// `SSEContext` is `Sendable`, so callers are free to send from several tasks at
/// once (a heartbeat alongside a main event loop, or a fan-in from multiple
/// producers). That is only safe because each event reaches Vapor as exactly one
/// `writeBuffer` call, which Vapor dispatches onto the connection's event loop
/// as a single unit.
///
/// These tests pin that invariant down. If a future change ever splits an event
/// across multiple writes, concurrent senders could splice one event into the
/// middle of another, and the write-count assertions below start failing.
@Suite("SSE concurrency guarantees")
struct SSEConcurrencyTests {
    @Test func eachSendPerformsExactlyOneWrite() async throws {
        struct Payload: Codable, Sendable { var status: String }

        let writer = RecordingWriter()
        let sse = SSEContext(writer: writer, encoder: .sse)

        try await sse.send("plain")
        try await sse.send(event: "named", data: "value")
        try await sse.send(Payload(status: "ok"))
        try await sse.send(event: "typed", data: Payload(status: "ok"))
        try await sse.sendComment("keep-alive")
        try await sse.send(ServerSentEvent(id: "1", event: "full", data: "body", retry: 3000))

        #expect(writer.writes.count == 6)
        #expect(writer.writes == [
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
        let writer = RecordingWriter()
        let sse = SSEContext(writer: writer, encoder: .sse)

        try await sse.send("first\nsecond\nthird")

        #expect(writer.writes.count == 1)
        #expect(writer.writes.first == "data: first\ndata: second\ndata: third\n\n")
    }

    /// Large payloads are the most likely candidate for a well-meaning future
    /// refactor to start chunking. They must not be split either.
    @Test func largePayloadIsASingleWrite() async throws {
        let writer = RecordingWriter()
        let sse = SSEContext(writer: writer, encoder: .sse)

        let payload = String(repeating: "x", count: 512 * 1024)
        try await sse.send(payload)

        #expect(writer.writes.count == 1)
        #expect(writer.writes.first == "data: \(payload)\n\n")
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

            try await app.testing(method: .running(hostname: "127.0.0.1", port: 0))
                .test(.GET, "events") { res async in
                    let events = res.body.string
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

            try await app.testing(method: .running(hostname: "127.0.0.1", port: 0))
                .test(.GET, "events") { res async in
                    let events = res.body.string
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
