import Foundation
import Observation
import OroroCore
import OroroDesign

@MainActor @Observable public final class SettingsViewModel {
    public private(set) var email: String?
    /// Nil = Off.
    public private(set) var subtitleLanguage: String?
    public private(set) var autoplayNext = true
    public private(set) var simulatedSurround = true
    /// True when the last playback output had fewer than 6 channels (surround is not in use there).
    public private(set) var outputIsStereo = false
    public private(set) var lastUpdated: Date?
    public private(set) var imageCacheBytes = 0
    public private(set) var isRefreshing = false
    /// Language codes offered besides Off.
    public let languages = ["en", "ru", "es", "de", "fr", "it", "pt", "pl", "tr", "cs"]
    public let version: String

    private let environment: AppEnvironment
    private let session: AppSession
    private let clearImages: () async -> Void
    private let imageUsage: () async -> Int
    private let lastOutputChannels: @MainActor () -> Int?

    public init(
        environment: AppEnvironment,
        session: AppSession,
        clearImages: @escaping () async -> Void = ImageCache.clear,
        imageUsage: @escaping () async -> Int = ImageCache.diskUsage,
        lastOutputChannels: @escaping @MainActor () -> Int? = { AudioOutput.lastObservedChannelCount }
    ) {
        self.environment = environment
        self.session = session
        self.clearImages = clearImages
        self.imageUsage = imageUsage
        self.lastOutputChannels = lastOutputChannels
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        version = "\(short) (\(build))"
    }

    public func load() async {
        email = environment.credentials.load()?.email
        let preferences = await environment.library.snapshot().preferences
        subtitleLanguage = preferences.subtitleLanguage
        autoplayNext = preferences.autoplayNext
        simulatedSurround = preferences.simulatedSurround
        outputIsStereo = lastOutputChannels().map { $0 < 6 } ?? false
        lastUpdated = await environment.catalog.lastUpdated()
        imageCacheBytes = await imageUsage()
    }

    public func setSubtitleLanguage(_ code: String?) async {
        subtitleLanguage = code
        await environment.library.update { $0.preferences.subtitleLanguage = code }
    }

    public func setAutoplay(_ enabled: Bool) async {
        autoplayNext = enabled
        await environment.library.update { $0.preferences.autoplayNext = enabled }
    }

    public func setSimulatedSurround(_ enabled: Bool) async {
        simulatedSurround = enabled
        await environment.library.update { $0.preferences.simulatedSurround = enabled }
    }

    public func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await session.refresh(force: true)
        lastUpdated = await environment.catalog.lastUpdated()
        isRefreshing = false
    }

    public func clearImageCache() async {
        await clearImages()
        imageCacheBytes = await imageUsage()
    }

    /// Empties My List, progress and watch history; the preferences survive.
    public func eraseLibrary() async {
        let preferences = await environment.library.snapshot().preferences
        await environment.library.erase()
        await environment.library.update { $0.preferences = preferences }
    }

    public func signOut() async {
        await session.signOut()
        email = nil
    }
}
