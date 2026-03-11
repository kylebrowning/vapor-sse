/// A single Server-Sent Event as defined by the SSE specification.
///
/// See: https://html.spec.whatwg.org/multipage/server-sent-events.html
public struct ServerSentEvent: Sendable {
    /// The event ID. Sets the last event ID value of the event source.
    public var id: String?

    /// The event type. If specified, clients will dispatch this as a named event.
    public var event: String?

    /// The event data. Multiple lines are supported.
    public var data: String?

    /// The reconnection time in milliseconds. Clients use this to determine
    /// how long to wait before attempting to reconnect.
    public var retry: Int?

    /// A comment line. Useful as a keep-alive or for debugging.
    public var comment: String?

    public init(
        id: String? = nil,
        event: String? = nil,
        data: String? = nil,
        retry: Int? = nil,
        comment: String? = nil
    ) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
        self.comment = comment
    }

    /// Serializes the event to the SSE wire format.
    public func serialize() -> String {
        var result = ""

        if let comment {
            for line in comment.split(separator: "\n", omittingEmptySubsequences: false) {
                result += ": \(line)\n"
            }
        }

        if let id {
            result += "id: \(id)\n"
        }

        if let event {
            result += "event: \(event)\n"
        }

        if let retry {
            result += "retry: \(retry)\n"
        }

        if let data {
            for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
                result += "data: \(line)\n"
            }
        }

        result += "\n"
        return result
    }
}
