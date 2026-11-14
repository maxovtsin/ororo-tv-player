import Foundation
import OroroCore
import OroroTestSupport
import Testing
@testable import OroroFeatures

@Suite @MainActor struct SettingsViewModelTests {
    private final class Usage: @unchecked Sendable {
        var bytes = 4_096
        var clearCalls = 0
    }

    private struct Rig {
        let model: SettingsViewModel
        let library: InMemoryLibraryStore
        let catalog: FakeCatalog
        let credentials: InMemoryCredentialStore
        let session: AppSession
        let usage: Usage
    }

    private func makeRig(library: Library = Library(), lastOutputChannels: @escaping @MainActor () -> Int? = { nil }) -> Rig {
        let store = InMemoryLibraryStore(library)
        let catalog = FakeCatalog(current: Samples.catalog)
        let credentials = InMemoryCredentialStore(Credentials(email: "viewer@example.com", password: "hunter2"))
        let environment = AppEnvironment(
            api: FakeAPI(), catalog: catalog, library: store, details: FakeDetails(),
            credentials: credentials, newEpisodes: FakeNewEpisodes()
        )
        let usage = Usage()
        let session = AppSession(environment: environment)
        let model = SettingsViewModel(
            environment: environment,
            session: session,
            clearImages: { usage.clearCalls += 1; usage.bytes = 0 },
            imageUsage: { usage.bytes },
            lastOutputChannels: lastOutputChannels
        )
        return Rig(model: model, library: store, catalog: catalog, credentials: credentials, session: session, usage: usage)
    }

    @Test func loadReadsPreferencesAndAccount() async {
        var library = Library()
        library.preferences = Preferences(subtitleLanguage: "ru", autoplayNext: false)
        let rig = makeRig(library: library)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        await rig.catalog.configure { $0.lastUpdatedDate = stamp }
        await rig.model.load()
        #expect(rig.model.email == "viewer@example.com")
        #expect(rig.model.subtitleLanguage == "ru")
        #expect(rig.model.autoplayNext == false)
        #expect(rig.model.lastUpdated == stamp)
        #expect(rig.model.imageCacheBytes == 4_096)
        #expect(rig.model.languages == ["en", "ru", "es", "de", "fr", "it", "pt", "pl", "tr", "cs"])
        #expect(!rig.model.version.isEmpty)
    }

    @Test func setSubtitleLanguageIncludingOffPersists() async {
        let rig = makeRig()
        await rig.model.setSubtitleLanguage("de")
        #expect(rig.model.subtitleLanguage == "de")
        #expect(await rig.library.snapshot().preferences.subtitleLanguage == "de")
        await rig.model.setSubtitleLanguage(nil)
        #expect(rig.model.subtitleLanguage == nil)
        #expect(await rig.library.snapshot().preferences.subtitleLanguage == nil)
    }

    @Test func surroundSettingLoadsAndPersists() async {
        var library = Library()
        library.preferences = Preferences(subtitleLanguage: "ru", autoplayNext: false)
        let rig = makeRig(library: library)
        await rig.model.load()
        #expect(rig.model.simulatedSurround == true)
        await rig.model.setSimulatedSurround(false)
        #expect(rig.model.simulatedSurround == false)
        let preferences = await rig.library.snapshot().preferences
        #expect(preferences.simulatedSurround == false)
        #expect(preferences.subtitleLanguage == "ru")
        #expect(preferences.autoplayNext == false)
    }

    @Test(arguments: [(nil as Int?, false), (2, true), (6, false)])
    func stereoHintFollowsTheLastPlaybackOutput(channels: Int?, expected: Bool) async {
        let rig = makeRig(lastOutputChannels: { channels })
        await rig.model.load()
        #expect(rig.model.outputIsStereo == expected)
    }

    @Test func setAutoplayPersists() async {
        let rig = makeRig()
        await rig.model.setAutoplay(false)
        #expect(rig.model.autoplayNext == false)
        #expect(await rig.library.snapshot().preferences.autoplayNext == false)
    }

    @Test func refreshCallsForceRefresh() async {
        let rig = makeRig()
        let stale = Date(timeIntervalSince1970: 1_700_000_000)
        await rig.catalog.configure { $0.lastUpdatedDate = stale }
        await rig.model.load()
        #expect(rig.model.lastUpdated == stale)
        let before = Date()
        await rig.model.refreshCatalog()
        #expect(rig.model.isRefreshing == false)
        #expect(await rig.catalog.refreshCalls == 1)
        #expect(await rig.catalog.lastRefreshForce == true)
        // The fake stamps the refresh time; the model must show what the catalog now reports.
        let reported = await rig.catalog.lastUpdated()
        #expect(rig.model.lastUpdated == reported)
        #expect((rig.model.lastUpdated ?? .distantPast) >= before)
    }

    @Test func clearImageCacheCallsThroughAndReloadsUsage() async {
        let rig = makeRig()
        await rig.model.load()
        #expect(rig.model.imageCacheBytes == 4_096)
        await rig.model.clearImageCache()
        #expect(rig.usage.clearCalls == 1)
        #expect(rig.model.imageCacheBytes == 0)
    }

    @Test func eraseLibraryEmptiesStore() async {
        var library = Library()
        library.myList = [MyListItem(title: TitleID(kind: .show, id: 1), addedAt: Date(timeIntervalSince1970: 0))]
        library.watchedMovies = [5]
        library.preferences = Preferences(subtitleLanguage: "fr", autoplayNext: false)
        let rig = makeRig(library: library)
        await rig.model.eraseLibrary()
        let after = await rig.library.snapshot()
        #expect(after.myList.isEmpty)
        #expect(after.watchedMovies.isEmpty)
        #expect(await rig.library.eraseCount == 1)
        #expect(after.preferences == Preferences(subtitleLanguage: "fr", autoplayNext: false))
    }

    @Test func signOutCallsSession() async {
        let rig = makeRig()
        await rig.model.load()
        #expect(rig.model.email == "viewer@example.com")
        await rig.model.signOut()
        #expect(rig.model.email == nil)
        #expect(rig.credentials.load() == nil)
        #expect(rig.credentials.clearCount == 1)
        #expect(rig.session.state == .signedOut)
        #expect(await rig.catalog.clearCalls == 1)
    }
}
