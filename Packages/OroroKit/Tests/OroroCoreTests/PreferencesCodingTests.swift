import Foundation
import Testing
@testable import OroroCore

@Suite struct PreferencesCodingTests {
    @Test func preferencesSavedBeforeSurroundDecodeWithItOn() throws {
        let old = Data(#"{"subtitleLanguage":"ru","autoplayNext":false}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: old)
            == Preferences(subtitleLanguage: "ru", autoplayNext: false, simulatedSurround: true))
    }

    @Test func preferencesRoundTripSurroundOff() throws {
        let value = Preferences(subtitleLanguage: nil, autoplayNext: true, simulatedSurround: false)
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)) == value)
    }
}
