import OroroFeatures
import SwiftUI

@main
struct OroroApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            AppRootView().environment(\.appEnvironment, environment)
        }
    }
}
