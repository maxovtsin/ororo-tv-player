import OroroDesign
import OroroFeatures
import OroroStore
import SwiftUI

@main
struct OroroApp: App {
    private let environment: AppEnvironment

    init() {
        ImageCache.configure()
        LegacyCleanup.run()
        environment = AppEnvironment.live()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView().environment(\.appEnvironment, environment)
        }
    }
}
