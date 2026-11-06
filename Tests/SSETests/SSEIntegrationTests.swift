import Testing
import Vapor
import VaporTesting
@testable import SSE

@Suite("SSE integration")
struct SSEIntegrationTests {
    @Test func sseResponseHeaders() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send("hello")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                #expect(res.status == .ok)
                #expect(res.headers[.contentType] == "text/event-stream")
                #expect(res.headers[.cacheControl] == "no-cache")
                #expect(res.headers[.connection] == "keep-alive")
            }
        }
    }

    @Test func sseStringSend() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send("first")
                    try await sse.send("second")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                #expect(body == "data: first\n\ndata: second\n\n")
            }
        }
    }

    @Test func sseNamedEvent() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send(event: "ping", data: "alive")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                #expect(body == "event: ping\ndata: alive\n\n")
            }
        }
    }

    @Test func sseJSONSend() async throws {
        struct Payload: Codable, Sendable {
            var count: Int
            var message: String
        }

        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send(Payload(count: 42, message: "hello"))
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                // sortedKeys ensures deterministic output
                #expect(body == "data: {\"count\":42,\"message\":\"hello\"}\n\n")
            }
        }
    }

    @Test func sseNamedEventWithJSON() async throws {
        struct Update: Codable, Sendable {
            var status: String
        }

        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send(event: "status", data: Update(status: "ok"))
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                #expect(body == "event: status\ndata: {\"status\":\"ok\"}\n\n")
            }
        }
    }

    @Test func sseComment() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.sendComment("keep-alive")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                #expect(body == ": keep-alive\n\n")
            }
        }
    }

    @Test func sseFullEvent() async throws {
        try await withApp { app in
            app.get("events") { req in
                req.sse { sse in
                    try await sse.send(ServerSentEvent(
                        id: "1",
                        event: "message",
                        data: "hello",
                        retry: 3000
                    ))
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                let body = try await res.body.requireString()
                #expect(body == "id: 1\nevent: message\nretry: 3000\ndata: hello\n\n")
            }
        }
    }

    @Test func sseLastEventID() async throws {
        try await withApp { app in
            app.get("events") { req in
                let lastID = req.lastEventID ?? "none"
                return req.sse { sse in
                    try await sse.send("last-id: \(lastID)")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events", headers: [.lastEventID: "42"])
                let body = try await res.body.requireString()
                #expect(body == "data: last-id: 42\n\n")
            }
        }
    }

    @Test func sseResponseStaticFactory() async throws {
        try await withApp { app in
            app.get("events") { req in
                Response.sse { sse in
                    try await sse.send("via-static")
                }
            }

            try await app.testing { client in
                let res = try await client.get("events")
                try #expect(await res.body.requireString() == "data: via-static\n\n")
            }
        }
    }
}
