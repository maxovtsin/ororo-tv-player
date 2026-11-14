import Testing
@testable import OroroDesign

@Suite struct ControlsTests {
    @Test func badgeAccessibilityLabels() {
        #expect(BadgeKind.imdb(8.3).accessibilityLabel == "IMDb rating 8.3")
        #expect(BadgeKind.imdb(7).accessibilityLabel == "IMDb rating 7.0")
        #expect(BadgeKind.hd.accessibilityLabel == "High definition")
        #expect(BadgeKind.sd.accessibilityLabel == "Standard definition")
        #expect(BadgeKind.cc.accessibilityLabel == "Subtitles available")
        #expect(BadgeKind.new.accessibilityLabel == "New")
        #expect(BadgeKind.text("Ongoing").accessibilityLabel == "Ongoing")
    }

    @Test func metadataLineAccessibilityLabelJoinsItems() {
        let items: [MetadataItem] = [.badge(.imdb(8.3)), .text("2025"), .badge(.hd)]
        #expect(MetadataLine.accessibilityLabel(for: items) == "IMDb rating 8.3, 2025, High definition")
        #expect(MetadataLine.accessibilityLabel(for: []).isEmpty)
    }
}
