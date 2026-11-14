import OroroCore
import OroroDesign
import SwiftUI

/// "Subtitles: English" button that sets the app-wide preferred language (Off + languages); the same preference as
/// in Settings.
struct SubtitleLanguagePicker: View {
    let selection: String?
    /// The title's languages; nil until known. The current preference is always offered too.
    let available: [String]?
    let onSelect: (String?) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker(selection: binding) {
                Text(Self.offTitle).tag(String?.none)
                ForEach(options, id: \.self) { code in
                    Text(verbatim: Display.languageName(code, locale: locale)).tag(String?.some(code))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label(title, systemImage: "captions.bubble")
        }
        .menuStyle(.button)
        .glassControl()
        .accessibilityLabel(title)
    }

    var title: String {
        let name = selection.map { Display.languageName($0, locale: locale) } ?? Self.offTitle
        return String(localized: "detail.subtitles", defaultValue: "Subtitles: \(name)", bundle: .module)
    }

    /// Available languages in their order, plus the current preference when it is missing.
    var options: [String] {
        var codes = available ?? []
        if let selection, !codes.contains(selection) { codes.insert(selection, at: 0) }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    private var binding: Binding<String?> {
        Binding(get: { selection }, set: { onSelect($0) })
    }

    private static var offTitle: String {
        String(localized: "detail.subtitles.off", defaultValue: "Off", bundle: .module)
    }
}

#Preview("Subtitle picker") {
    VStack(alignment: .leading) {
        SubtitleLanguagePicker(selection: "en", available: ["en", "ru", "es"]) { _ in }
        SubtitleLanguagePicker(selection: nil, available: nil) { _ in }
    }
    .padding()
}
