import OroroCore
import SwiftUI

/// Maps a pushed `Route` to its screen.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .show(let id):
            DetailScreen(id: TitleID(kind: .show, id: id))
        case .movie(let id):
            DetailScreen(id: TitleID(kind: .movie, id: id))
        case .browse(let query):
            BrowseGridScreen(query: query)
        }
    }
}
