import Foundation
import Testing
@testable import OroroFeatures

/// Reads a package `Localizable.xcstrings` (and that module's sources) straight from the source tree.
struct LocalisationCatalog {
    enum Module: String, CaseIterable {
        case design = "OroroDesign"
        case features = "OroroFeatures"
    }

    let strings: [String: [String: Any]]

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OroroFeaturesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // OroroUI
    }

    static func sourcesDirectory(_ module: Module) -> URL {
        packageRoot.appending(path: "Sources/\(module.rawValue)")
    }

    static func load(_ module: Module) throws -> LocalisationCatalog {
        let url = sourcesDirectory(module).appending(path: "Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return LocalisationCatalog(strings: object?["strings"] as? [String: [String: Any]] ?? [:])
    }

    /// Every value of `language` for `key`: the plain string unit, or each plural variant (keyed by category).
    func values(_ key: String, language: String) -> [String: String] {
        guard let localization = (strings[key]?["localizations"] as? [String: Any])?[language] as? [String: Any] else { return [:] }
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return ["": value]
        }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return plural.reduce(into: [:]) { result, pair in
            if let value = ((pair.value as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String {
                result[pair.key] = value
            }
        }
    }

    /// Literal keys of `String(localized: "<key>", …)` calls in the module's Swift sources.
    static func sourceKeys(_ module: Module) throws -> Set<String> {
        let pattern = try Regex(#"String\(\s*localized:\s*"([^"\\]+)""#)
        var keys = Set<String>()
        let enumerator = FileManager.default.enumerator(at: sourcesDirectory(module), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for match in source.matches(of: pattern) {
                if let key = match.output[1].substring { keys.insert(String(key)) }
            }
        }
        return keys
    }
}

@Suite struct LocalisationTests {
    private static let russian = GenreName.bundle(for: Locale(identifier: "ru_RU"))
    private static let english = GenreName.bundle(for: Locale(identifier: "en_US"))

    @Test(arguments: LocalisationCatalog.Module.allCases)
    func everyKeyHasRussian(_ module: LocalisationCatalog.Module) throws {
        let catalog = try LocalisationCatalog.load(module)
        #expect(!catalog.strings.isEmpty)
        for key in catalog.strings.keys {
            let values = catalog.values(key, language: "ru")
            #expect(!values.isEmpty, "\(module.rawValue): \(key) has no Russian value")
            #expect(values.values.allSatisfy { !$0.isEmpty }, "\(module.rawValue): \(key) has an empty Russian value")
        }
    }

    @Test(arguments: LocalisationCatalog.Module.allCases)
    func everyKeyHasEnglish(_ module: LocalisationCatalog.Module) throws {
        let catalog = try LocalisationCatalog.load(module)
        for key in catalog.strings.keys {
            let values = catalog.values(key, language: "en")
            #expect(!values.isEmpty && values.values.allSatisfy { !$0.isEmpty }, "\(module.rawValue): \(key) has no English value")
        }
    }

    @Test(arguments: LocalisationCatalog.Module.allCases)
    func everySourceKeyIsInItsModuleCatalog(_ module: LocalisationCatalog.Module) throws {
        let keys = try LocalisationCatalog.sourceKeys(module)
        let catalog = try LocalisationCatalog.load(module)
        #expect(!keys.isEmpty)
        for key in keys.sorted() {
            #expect(catalog.strings[key] != nil, "\(key) is missing from \(module.rawValue)'s catalog")
        }
    }

    @Test(arguments: LocalisationCatalog.Module.allCases)
    func russianKeepsTheEnglishPlaceholders(_ module: LocalisationCatalog.Module) throws {
        let catalog = try LocalisationCatalog.load(module)
        for key in catalog.strings.keys {
            let english = Set(catalog.values(key, language: "en").values.map(Self.placeholders))
            let russian = Set(catalog.values(key, language: "ru").values.map(Self.placeholders))
            #expect(english.count <= 1 && english == russian, "\(module.rawValue): \(key) placeholders differ")
        }
    }

    @Test func countsUseRussianPluralForms() {
        // The plural category follows the formatting locale (Locale.current in the app), the text the bundle.
        let bundle = Self.russian
        let ru = Locale(identifier: "ru_RU")
        #expect(String(localized: "browse.grid.count", defaultValue: "\(1) titles", bundle: bundle, locale: ru) == "1 название")
        #expect(String(localized: "browse.grid.count", defaultValue: "\(3) titles", bundle: bundle, locale: ru) == "3 названия")
        #expect(String(localized: "browse.grid.count", defaultValue: "\(5) titles", bundle: bundle, locale: ru) == "5 названий")
        #expect(String(localized: "browse.grid.count", defaultValue: "\(21) titles", bundle: bundle, locale: ru) == "21 название")
        #expect(String(localized: "detail.seasonCount", defaultValue: "\(1) Seasons", bundle: bundle, locale: ru) == "1 сезон")
        #expect(String(localized: "detail.seasonCount", defaultValue: "\(2) Seasons", bundle: bundle, locale: ru) == "2 сезона")
        #expect(String(localized: "detail.seasonCount", defaultValue: "\(11) Seasons", bundle: bundle, locale: ru) == "11 сезонов")
    }

    @Test func countsUseEnglishPluralForms() {
        let bundle = Self.english
        #expect(String(localized: "browse.grid.count", defaultValue: "\(1) titles", bundle: bundle) == "1 title")
        #expect(String(localized: "browse.grid.count", defaultValue: "\(30) titles", bundle: bundle) == "30 titles")
        #expect(String(localized: "detail.seasonCount", defaultValue: "\(1) Seasons", bundle: bundle) == "1 Season")
        #expect(String(localized: "detail.seasonCount", defaultValue: "\(2) Seasons", bundle: bundle) == "2 Seasons")
    }

    @Test func russianInterpolationKeepsArgumentOrder() {
        let bundle = Self.russian
        #expect(String(localized: "hero.accessibility.position", defaultValue: "\(2) of \(6)", bundle: bundle) == "2 из 6")
        #expect(String(localized: "search.noResults", defaultValue: "No results for '\("Dune")'", bundle: bundle)
            == "Ничего не найдено по запросу «Dune»")
    }

    /// Format specifiers in order of argument position, e.g. "%1$lld of %2$lld" and "%lld of %lld" → ["lld", "lld"].
    private static func placeholders(_ value: String) -> [String] {
        let pattern = /%(?:(\d+)\$)?(lld|ld|d|@|f|\.\df)/
        var positional: [(Int, String)] = []
        for (index, match) in value.matches(of: pattern).enumerated() {
            let position = match.output.1.flatMap { Int($0) } ?? index + 1
            positional.append((position, String(match.output.2)))
        }
        return positional.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
