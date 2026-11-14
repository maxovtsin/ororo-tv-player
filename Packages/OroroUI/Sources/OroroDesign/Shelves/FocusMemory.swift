import Observation

// STUB (T3) — implemented by Task D5.
@MainActor @Observable public final class FocusMemory {
    public init() {}

    public func remember(_ id: FocusID) {}

    public func last(screen: String) -> FocusID? {
        nil
    }

    public func item(screen: String, shelf: String) -> String? {
        nil
    }

    /// Index of the remembered item when stored.
    public func index(screen: String, shelf: String) -> Int? {
        nil
    }

    /// Remembered id if present; else same index clamped; else first; nil if empty.
    public func resolve(screen: String, shelf: String, available: [String]) -> String? {
        nil
    }

    /// Shelf id to restore vertical scroll to.
    public func verticalAnchor(screen: String) -> String? {
        nil
    }

    public func reset(screen: String) {}
}
