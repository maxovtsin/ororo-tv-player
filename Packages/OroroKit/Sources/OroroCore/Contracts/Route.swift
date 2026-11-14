public enum Route: Hashable, Codable, Sendable {
    case show(Int), movie(Int), browse(BrowseQuery)
}
