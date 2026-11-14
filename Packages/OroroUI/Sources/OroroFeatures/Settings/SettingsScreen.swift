import OroroCore
import OroroDesign
import SwiftUI

public struct SettingsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.appEnvironment) private var environment
    @Environment(TabRouter.self) private var router
    @State private var model: SettingsViewModel?
    @State private var confirmErase = false
    @State private var confirmSignOut = false
    #if DEBUG && os(tvOS)
    @AppStorage(SurroundDebug.defaultsKey) private var surroundSignal = ""
    #endif

    public init() {}

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        // A short form: Menu always goes to the tab bar.
        .onAppear { router.isAtTop = true }
        .task {
            let model = self.model ?? SettingsViewModel(environment: environment, session: session)
            self.model = model
            await model.load()
        }
    }

    private func content(_ model: SettingsViewModel) -> some View {
        Form {
            Section(String(localized: "settings.account", defaultValue: "Account", bundle: .module)) {
                LabeledContent(
                    String(localized: "settings.email", defaultValue: "Email", bundle: .module),
                    value: model.email ?? String(localized: "settings.notSignedIn", defaultValue: "Not signed in", bundle: .module)
                )
                ActionButton(
                    String(localized: "settings.signOut", defaultValue: "Sign Out", bundle: .module),
                    systemImage: "rectangle.portrait.and.arrow.right"
                ) {
                    confirmSignOut = true
                }
            }
            Section(String(localized: "settings.playback", defaultValue: "Playback", bundle: .module)) {
                Picker(
                    String(localized: "settings.subtitleLanguage", defaultValue: "Subtitle language", bundle: .module),
                    selection: Binding(get: { model.subtitleLanguage }, set: { code in Task { await model.setSubtitleLanguage(code) } })
                ) {
                    Text(String(localized: "settings.subtitlesOff", defaultValue: "Off", bundle: .module)).tag(String?.none)
                    ForEach(model.languages, id: \.self) { code in
                        Text(verbatim: Display.languageName(code, locale: .current)).tag(String?.some(code))
                    }
                }
                Toggle(
                    String(localized: "settings.autoplayNext", defaultValue: "Autoplay next episode", bundle: .module),
                    isOn: Binding(get: { model.autoplayNext }, set: { enabled in Task { await model.setAutoplay(enabled) } })
                )
            }
            Section(String(localized: "settings.catalog", defaultValue: "Catalog", bundle: .module)) {
                LabeledContent(String(localized: "settings.lastUpdated", defaultValue: "Last updated", bundle: .module)) {
                    if let date = model.lastUpdated {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else {
                        Text(String(localized: "settings.never", defaultValue: "Never", bundle: .module))
                    }
                }
                ActionButton(
                    String(localized: "settings.refreshCatalog", defaultValue: "Refresh catalog", bundle: .module),
                    systemImage: "arrow.clockwise", isLoading: model.isRefreshing
                ) {
                    Task { await model.refreshCatalog() }
                }
            }
            Section(String(localized: "settings.storage", defaultValue: "Storage", bundle: .module)) {
                LabeledContent(
                    String(localized: "settings.imageCache", defaultValue: "Image cache", bundle: .module),
                    value: Int64(model.imageCacheBytes).formatted(.byteCount(style: .file))
                )
                ActionButton(
                    String(localized: "settings.clearImageCache", defaultValue: "Clear image cache", bundle: .module),
                    systemImage: "photo.stack"
                ) {
                    Task { await model.clearImageCache() }
                }
                ActionButton(
                    String(localized: "settings.eraseLibrary", defaultValue: "Erase My List and watch history", bundle: .module),
                    systemImage: "trash"
                ) {
                    confirmErase = true
                }
            }
            Section {
                LabeledContent(String(localized: "settings.version", defaultValue: "Version", bundle: .module), value: model.version)
            }
            #if DEBUG && os(tvOS)
            Section {
                Picker(selection: $surroundSignal) {
                    Text(verbatim: "Off").tag("")
                    Text(verbatim: "Speaker test").tag(SurroundDebugSignal.speakerTest.rawValue)
                    Text(verbatim: "Steady tone").tag(SurroundDebugSignal.steadyTone.rawValue)
                } label: {
                    Text(verbatim: "Surround test signal")
                }
            } header: {
                Text(verbatim: "Debug")
            }
            #endif
        }
        .confirmationDialog(
            String(localized: "settings.eraseConfirmTitle", defaultValue: "Erase My List and watch history?", bundle: .module),
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.eraseConfirm", defaultValue: "Erase", bundle: .module), role: .destructive) {
                Task { await model.eraseLibrary() }
            }
            Button(String(localized: "settings.cancel", defaultValue: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.eraseConfirmMessage", defaultValue: "This cannot be undone.", bundle: .module))
        }
        .confirmationDialog(
            String(localized: "settings.signOutConfirmTitle", defaultValue: "Sign out of Ororo?", bundle: .module),
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.signOutConfirm", defaultValue: "Sign Out", bundle: .module), role: .destructive) {
                Task { await model.signOut() }
            }
            Button(String(localized: "settings.cancel", defaultValue: "Cancel", bundle: .module), role: .cancel) {}
        }
    }
}

#Preview {
    SettingsScreen()
        .environment(AppSession(environment: .preview()))
        .environment(TabRouter())
}
