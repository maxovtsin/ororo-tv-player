import OroroFeatures
import SwiftUI

@main
struct OroroTVApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            AppRootView().environment(\.appEnvironment, environment)
        }
    }
}
