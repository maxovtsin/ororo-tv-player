@testable import OroroFeatures
import Testing

@Suite struct AudioOptionChoiceTests {
    private typealias Candidate = AudioOptionChoice.Candidate

    @Test func picksTheSixChannelOptionOverTheDefaultStereoOne() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let surround = Candidate(index: 1, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, surround], current: stereo) == surround)
    }

    @Test func prefersTheCurrentLanguage() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let otherSurround = Candidate(index: 1, language: "ru", channels: 6)
        let surround = Candidate(index: 2, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, otherSurround, surround], current: stereo) == surround)
    }

    @Test func prefersTheCurrentLanguageEvenWithFewerChannels() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let other = Candidate(index: 1, language: "ru", channels: 8)
        let surround = Candidate(index: 2, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, other, surround], current: stereo) == surround)
    }

    @Test func neverSwitchesLanguage() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let otherSurround = Candidate(index: 1, language: "ru", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, otherSurround], current: stereo) == nil)
    }

    @Test func aNilLanguageMatchesOnlyNil() {
        let unlabelled = Candidate(index: 0, language: nil, channels: 2)
        let english = Candidate(index: 1, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [unlabelled, english], current: unlabelled) == nil)
        let unlabelledSurround = Candidate(index: 2, language: nil, channels: 6)
        #expect(AudioOptionChoice.best(among: [unlabelled, english, unlabelledSurround], current: unlabelled)
                == unlabelledSurround)
    }

    @Test func theCurrentOptionIsKeptOnATie() {
        let surroundHD = Candidate(index: 0, language: "en", channels: 6)
        let surroundSD = Candidate(index: 1, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [surroundHD, surroundSD], current: surroundSD) == surroundSD)
    }

    @Test func anyLanguageWithoutACurrentOption() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let other = Candidate(index: 1, language: "ru", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, other], current: nil) == other)
    }

    @Test func picksTheMostChannels() {
        let six = Candidate(index: 0, language: "en", channels: 6)
        let eight = Candidate(index: 1, language: "en", channels: 8)
        #expect(AudioOptionChoice.best(among: [six, eight], current: six) == eight)
    }

    @Test func nilWhenNoOptionHasMoreThanTwoChannels() {
        let unknown = [Candidate(index: 0, language: "en", channels: nil), Candidate(index: 1, language: "en", channels: nil)]
        #expect(AudioOptionChoice.best(among: unknown, current: unknown[0]) == nil)
        let stereo = [Candidate(index: 0, language: "en", channels: 2), Candidate(index: 1, language: "ru", channels: 1),
                      Candidate(index: 2, language: "en", channels: nil)]
        #expect(AudioOptionChoice.best(among: stereo, current: stereo[0]) == nil)
        #expect(AudioOptionChoice.best(among: [], current: nil) == nil)
    }

    @Test func tiesKeepTheFirstInOrder() {
        let stereo = Candidate(index: 0, language: "en", channels: 2)
        let surroundHD = Candidate(index: 1, language: "en", channels: 6)
        let surroundSD = Candidate(index: 2, language: "en", channels: 6)
        #expect(AudioOptionChoice.best(among: [stereo, surroundHD, surroundSD], current: stereo) == surroundHD)
    }
}
