import Foundation
import OroroTestSupport
import Testing
@testable import OroroFeatures

@Suite struct GenreNameTests {
    private static let russian = Locale(identifier: "ru_RU")
    private static let english = Locale(identifier: "en_US")

    @Test func knownGenreIsTranslatedInRussian() {
        #expect(GenreName.localized("Comedy", locale: Self.russian) == "Комедия")
        #expect(GenreName.localized("Comedy", locale: Self.russian) != "Comedy")
        #expect(GenreName.localized("Sci-Fi", locale: Self.russian) == "Фантастика")
        #expect(GenreName.localized("TV Movie", locale: Self.russian) == "Телефильм")
    }

    @Test func knownGenreStaysEnglishInEnglish() {
        #expect(GenreName.localized("Comedy", locale: Self.english) == "Comedy")
        #expect(GenreName.localized("TV Movie", locale: Self.english) == "TV Movie")
    }

    @Test func unknownGenreFallsBack() {
        #expect(GenreName.localized("Space Opera Noir", locale: Self.russian) == "Space Opera Noir")
        #expect(GenreName.localized("Space Opera Noir", locale: Self.english) == "Space Opera Noir")
    }

    @Test func keyIsLowercasedWithUnderscoresForSpaces() {
        #expect(GenreName.key(for: "TV Movie") == "genre.tv_movie")
        #expect(GenreName.key(for: "Sci-Fi") == "genre.sci-fi")
        #expect(GenreName.key(for: "Reality-TV") == "genre.reality-tv")
    }

    @Test func all27FixtureGenresHaveKeys() throws {
        // The recorded fixtures carry 24 of the 27 live genres; every one of them must be in the catalog.
        var genres = Set<String>()
        for (name, field) in [("shows", "shows"), ("movies", "movies")] {
            let object = try JSONSerialization.jsonObject(with: Fixtures.data(name)) as? [String: Any]
            let items = try #require(object?[field] as? [[String: Any]])
            for item in items { genres.formUnion(item["array_genres"] as? [String] ?? []) }
        }
        #expect(genres.count >= 24)
        let strings = try LocalisationCatalog.load(.features).strings
        for genre in genres.sorted() {
            let entry = strings[GenreName.key(for: genre)]
            #expect(entry != nil, "missing catalog key for \(genre)")
            #expect(GenreName.localized(genre, locale: Self.russian) != GenreName.key(for: genre))
        }
    }
}
