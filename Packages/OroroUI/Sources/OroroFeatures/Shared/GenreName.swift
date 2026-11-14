import Foundation

/// Display names for API genre strings ("Comedy", "Sci-Fi", "TV Movie").
/// Each genre is a catalog key `genre.<lowercased, spaces→_>`; unknown genres show the API string.
public enum GenreName {
    public static func localized(_ apiName: String, locale: Locale = .current) -> String {
        let key = key(for: apiName)
        let value = bundle(for: locale).localizedString(forKey: key, value: nil, table: nil)
        return value == key || value.isEmpty ? apiName : value
    }

    static func key(for apiName: String) -> String {
        "genre." + apiName.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    /// The module's `<language>.lproj` best matching `locale`; the module bundle itself when none matches.
    static func bundle(for locale: Locale) -> Bundle {
        let module = Bundle.module
        let preferences = [locale.identifier, locale.language.languageCode?.identifier].compactMap(\.self)
        guard let language = Bundle.preferredLocalizations(from: module.localizations, forPreferences: preferences).first,
              let path = module.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return module }
        return localized
    }
}
