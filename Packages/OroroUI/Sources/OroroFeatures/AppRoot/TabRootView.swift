import OroroCore
import OroroDesign
import SwiftUI

/// The tab bar: Home · Shows · Movies · My List · Search · Settings (gear only, trailing).
struct TabRootView: View {
    @Bindable var tabs: TabsModel

    var body: some View {
        TabView(selection: $tabs.selected) {
            Tab(String(localized: "appRoot.tab.home", defaultValue: "Home", bundle: .module),
                systemImage: "house", value: AppTab.home) {
                TabStack(router: tabs.router(.home)) { HomeScreen() }
            }
            Tab(String(localized: "appRoot.tab.shows", defaultValue: "Shows", bundle: .module),
                systemImage: "tv", value: AppTab.shows) {
                TabStack(router: tabs.router(.shows)) { BrowseTabScreen(kind: .show) }
            }
            Tab(String(localized: "appRoot.tab.movies", defaultValue: "Movies", bundle: .module),
                systemImage: "film", value: AppTab.movies) {
                TabStack(router: tabs.router(.movies)) { BrowseTabScreen(kind: .movie) }
            }
            Tab(String(localized: "appRoot.tab.myList", defaultValue: "My List", bundle: .module),
                systemImage: "bookmark", value: AppTab.myList) {
                TabStack(router: tabs.router(.myList)) { MyListScreen() }
            }
            Tab(String(localized: "appRoot.tab.search", defaultValue: "Search", bundle: .module),
                systemImage: "magnifyingglass", value: AppTab.search) {
                TabStack(router: tabs.router(.search)) { SearchScreen() }
            }
            Tab(value: AppTab.settings) {
                TabStack(router: tabs.router(.settings)) { SettingsScreen() }
            } label: {
                Label(String(localized: "appRoot.tab.settings", defaultValue: "Settings", bundle: .module),
                      systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
        }
        .environment(\.selectTab, SelectTabAction { [tabs] tab in tabs.selected = tab })
    }
}

/// One tab's `NavigationStack`, its router and its zoom namespace.
private struct TabStack<Root: View>: View {
    @Bindable var router: TabRouter
    @ViewBuilder let root: () -> Root
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $router.path) {
            root()
                .modifier(ScrollToTopOnMenu(router: router))
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(router)
        .environment(\.detailZoomNamespace, zoom)
    }
}

/// Menu at a scrolled tab root scrolls to top (root screens observe the token); at the top the system
/// default moves focus to the tab bar. Pushed screens are outside this modifier, so Menu pops them.
private struct ScrollToTopOnMenu: ViewModifier {
    let router: TabRouter

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.onExitCommand(perform: router.isAtTop ? nil : { router.scrollToTopToken += 1 })
        #else
        content
        #endif
    }
}

#Preview {
    TabRootView(tabs: TabsModel())
}
