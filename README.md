# vapor-sse

Server-Sent Events (SSE) for [Vapor](https://github.com/vapor/vapor).

## Installation

Add `vapor-sse` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kylebrowning/vapor-sse.git", from: "1.0.0-beta"),
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

## API

| Type | Description |
|------|-------------|
| `ServerSentEvent` | SSE event model with `id`, `event`, `data`, `retry`, `comment` |
| `SSEContext` | Handle for sending events over an active connection |
| `Request.sse(_:)` | Creates an SSE response from a route handler |
| `Response.sse(_:)` | Static factory for SSE responses |
| `Request.lastEventID` | The `Last-Event-ID` header value, if present |

## License

MIT. See [LICENSE](LICENSE).
