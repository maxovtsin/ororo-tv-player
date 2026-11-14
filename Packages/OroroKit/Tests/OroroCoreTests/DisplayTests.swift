import Foundation
import Testing
@testable import OroroCore

@Suite struct DisplayTests {
    private let gb = Locale(identifier: "en_GB")

    @Test func runtimeEnglish() {
        #expect(Display.runtime(minutes: 155, locale: gb) == "2h 35m")
        #expect(Display.runtime(minutes: 45, locale: gb) == "45m")
        #expect(Display.runtime(minutes: 120, locale: gb) == "2h")
        #expect(Display.runtime(minutes: 0, locale: gb) == "0m")
    }

    @Test func runtimeInRussianIsLocalised() {
        let ru = Display.runtime(minutes: 155, locale: Locale(identifier: "ru_RU"))
        #expect(!ru.isEmpty)
        #expect(ru != "2h 35m")
    }

    @Test func flagBuildsRegionalIndicators() {
        #expect(Display.flag("GB") == "🇬🇧")
        #expect(Display.flag("us") == "🇺🇸")
    }

    @Test func flagRejectsBadCodes() {
        #expect(Display.flag("") == nil)
        #expect(Display.flag("GBR") == nil)
        #expect(Display.flag("1A") == nil)
    }

    @Test func countryNameIsLocalised() {
        #expect(Display.countryName("GB", locale: gb) == "United Kingdom")
        #expect(Display.countryName("DE", locale: gb) == "Germany")
        #expect(Display.countryName("DE", locale: Locale(identifier: "de_DE")) == "Deutschland")
        #expect(Display.countryName("", locale: gb) == nil)
    }

    @Test func languageNameFallsBackToUppercasedCode() {
        #expect(Display.languageName("en", locale: gb) == "English")
        #expect(Display.languageName("ru", locale: gb) == "Russian")
        #expect(Display.languageName("zzzz", locale: gb) == "ZZZZ")
    }

    @Test func episodeLabelFormat() {
        #expect(Display.episodeLabel(season: 2, number: 5) == "S2 E5")
    }

    @Test func airdateFormat() {
        let midnightUTC = Date(timeIntervalSince1970: 1_743_292_800) // 2025-03-30T00:00:00Z
        #expect(Display.airdate(midnightUTC, locale: gb) == "30 Mar 2025")
        // Last second of the same UTC day; in America/New_York both instants fall on 29 Mar,
        // so equal output proves the result does not follow TimeZone.current.
        let endOfDayUTC = Date(timeIntervalSince1970: 1_743_379_199)
        #expect(Display.airdate(endOfDayUTC, locale: gb) == "30 Mar 2025")
        let nextMidnight = Date(timeIntervalSince1970: 1_743_379_200)
        #expect(Display.airdate(nextMidnight, locale: gb) == "31 Mar 2025")
    }

    @Test func newEpisodeAgoWithinFourteenDays() {
        let now = Date(timeIntervalSince1970: 1_743_336_000)
        let twoDays = now.addingTimeInterval(-2 * 86_400)
        #expect(Display.newEpisodeAgo(twoDays, now: now, locale: gb) == "2 days ago")
        let exactly14 = now.addingTimeInterval(-14 * 86_400)
        #expect(Display.newEpisodeAgo(exactly14, now: now, locale: gb) != nil)
    }

    @Test func newEpisodeAgoNilWhenOldOrFuture() {
        let now = Date(timeIntervalSince1970: 1_743_336_000)
        #expect(Display.newEpisodeAgo(now.addingTimeInterval(-15 * 86_400), now: now, locale: gb) == nil)
        #expect(Display.newEpisodeAgo(now.addingTimeInterval(60), now: now, locale: gb) == nil)
    }

    @Test func timecodeFormat() {
        #expect(Display.timecode(23 * 60 + 14) == "23:14")
        #expect(Display.timecode(3600 + 2 * 60 + 3) == "1:02:03")
        #expect(Display.timecode(5) == "0:05")
    }

    @Test func timecodeHandlesNaNAndNegative() {
        #expect(Display.timecode(.nan) == "0:00")
        #expect(Display.timecode(-30) == "0:00")
        #expect(Display.timecode(.infinity) == "0:00")
        #expect(!Display.timecode(Double.greatestFiniteMagnitude).isEmpty) // must not trap
    }

    @Test func qualityRangeFormat() {
        #expect(Display.qualityRange(lowest: "240p", highest: "1080p") == "240p–1080p")
        #expect(Display.qualityRange(lowest: "720p", highest: "720p") == "720p")
    }
}
