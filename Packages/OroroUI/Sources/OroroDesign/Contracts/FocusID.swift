public struct FocusID: Hashable, Sendable {
    public let screen: String
    public let shelf: String
    public let item: String

    public init(screen: String, shelf: String, item: String) {
        self.screen = screen
        self.shelf = shelf
        self.item = item
    }
}
