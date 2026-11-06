# vapor-sse

Server-Sent Events (SSE) for [Vapor](https://github.com/vapor/vapor).

## Requirements

| vapor-sse | Vapor | Swift | Platforms |
|-----------|-------|-------|-----------|
| 2.x | 5.0.0-beta.4+ | 6.4 | macOS 26.2, iOS 26.2 |
| 1.x | 4.121.3+ | 6.0 | macOS 10.15, iOS 13 |

The public API is the same in both. Code written against 1.x compiles unchanged on 2.x.

## Installation

Add `vapor-sse` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kylebrowning/vapor-sse.git", from: "2.0.0-beta"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "SSE", package: "vapor-sse"),
    ]),
]
```

## Usage

### Basic

```swift
import Vapor
import SSE

app.get("events") { req in
    req.sse { sse in
        for i in 0..<10 {
            try await sse.send("tick \(i)")
            try await Task.sleep(for: .seconds(1))
        }
    }
}
```

### Named Events

```swift
app.get("events") { req in
    req.sse { sse in
        try await sse.send(event: "ping", data: "alive")
    }
}
```

### JSON Data

Send any `Encodable` value and it's automatically serialized to JSON:

```swift
struct Status: Codable, Sendable {
    var users: Int
    var uptime: Double
}

app.get("status") { req in
    req.sse { sse in
        try await sse.send(Status(users: 42, uptime: 99.9))
        try await sse.send(event: "update", data: Status(users: 43, uptime: 100.0))
    }
}
```

A custom `JSONEncoder` can be passed if needed:

```swift
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

app.get("events") { req in
    req.sse(encoder: encoder) { sse in
        try await sse.send(MyPayload())
    }
}
```

### Full Control

Use `ServerSentEvent` directly for id, retry, and comments:

```swift
app.get("events") { req in
    req.sse { sse in
        try await sse.send(ServerSentEvent(
            id: "1",
            event: "message",
            data: "{\"hello\": \"world\"}",
            retry: 5000
        ))
        try await sse.sendComment("keep-alive")
    }
}
```

### Reconnect Support

Access the client's `Last-Event-ID` header on reconnect:

```swift
app.get("events") { req in
    let lastID = req.lastEventID
    return req.sse { sse in
        // Resume from lastID...
    }
}
```

### Static Factory

You can also use `Response.sse` directly:

```swift
app.get("events") { req in
    Response.sse { sse in
        try await sse.send("hello")
    }
}
```

### Sending from several tasks

`SSEContext` is `Sendable`, so a heartbeat can run alongside the real work:

```swift
app.get("events") { req in
    req.sse { sse in
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while true {
                    try await Task.sleep(for: .seconds(15))
                    try await sse.sendComment("keep-alive")
                }
            }
            for await update in updates() {
                try await sse.send(update)
            }
            group.cancelAll()
        }
    }
}
```

Each event is written whole, so concurrent sends never splice into each other. They have no defined order between them, though, so keep `id`-stamped events on one task.

`send` returns once the event has been written. If the client has gone away it throws, which is how a long-running handler finds out it should stop. Sending on a context after its handler has returned throws `SSEStreamClosedError`.

## API

| Type | Description |
|------|-------------|
| `ServerSentEvent` | SSE event model with `id`, `event`, `data`, `retry`, `comment` |
| `SSEContext` | Handle for sending events over an active connection |
| `Request.sse(_:)` | Creates an SSE response from a route handler |
| `Response.sse(_:)` | Static factory for SSE responses |
| `Request.lastEventID` | The `Last-Event-ID` header value, if present |
| `HTTPField.Name.lastEventID` | The `Last-Event-ID` header name |
| `SSEStreamClosedError` | Thrown when sending after the stream has ended |

## License

MIT. See [LICENSE](LICENSE).
