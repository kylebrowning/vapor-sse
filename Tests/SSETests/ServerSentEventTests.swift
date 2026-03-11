import Testing
@testable import SSE

@Suite("ServerSentEvent serialization")
struct ServerSentEventTests {
    @Test func dataOnly() {
        let event = ServerSentEvent(data: "hello")
        #expect(event.serialize() == "data: hello\n\n")
    }

    @Test func multilineData() {
        let event = ServerSentEvent(data: "line1\nline2\nline3")
        #expect(event.serialize() == "data: line1\ndata: line2\ndata: line3\n\n")
    }

    @Test func namedEvent() {
        let event = ServerSentEvent(event: "update", data: "payload")
        #expect(event.serialize() == "event: update\ndata: payload\n\n")
    }

    @Test func withID() {
        let event = ServerSentEvent(id: "42", data: "msg")
        #expect(event.serialize() == "id: 42\ndata: msg\n\n")
    }

    @Test func withRetry() {
        let event = ServerSentEvent(data: "reconnect", retry: 3000)
        #expect(event.serialize() == "retry: 3000\ndata: reconnect\n\n")
    }

    @Test func commentOnly() {
        let event = ServerSentEvent(comment: "keep-alive")
        #expect(event.serialize() == ": keep-alive\n\n")
    }

    @Test func allFields() {
        let event = ServerSentEvent(
            id: "1",
            event: "message",
            data: "hello",
            retry: 5000,
            comment: "debug"
        )
        #expect(event.serialize() == ": debug\nid: 1\nevent: message\nretry: 5000\ndata: hello\n\n")
    }

    @Test func emptyEvent() {
        let event = ServerSentEvent()
        #expect(event.serialize() == "\n")
    }
}
