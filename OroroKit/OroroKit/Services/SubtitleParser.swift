//
//  SubtitleParser.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public class SubtitleParser {

    public static func searchSubtitles(payload: [Interval],
                                       time: TimeInterval) -> String? {
        let item = payload
            .filter { time >= $0.from && time <= $0.to }
            .first
        guard let interval = item else { return nil }
        return interval.text
    }

    public static func parse(payload: String) -> [Interval] {
        var intervals = [Interval]()

        guard let lineRegex = try? NSRegularExpression(pattern: Constants.Pattern,
                                                       options: .caseInsensitive)
            else { return intervals }
        guard let indexRegex = try? NSRegularExpression(pattern: "^[0-9]+",
                                                        options: .caseInsensitive)
            else { return intervals }
        guard let regionsRegex = try? NSRegularExpression(pattern: "\\d{1,2}:\\d{1,2}:\\d{1,2}[,.]\\d{1,3}",
                                                          options: .caseInsensitive)
            else { return intervals }

        let matches = lineRegex.matches(in: payload,
                                        options: NSRegularExpression.MatchingOptions(rawValue: 0),
                                        range: NSRange(location: 0, length: payload.count))

        for match in matches {
            let line = payload.substring(with: match.range)

            // Get index
            let indexMatch = indexRegex.matches(in: line,
                                                options: NSRegularExpression.MatchingOptions(rawValue: 0),
                                                range: NSRange(location: 0, length: line.count))
            guard let i = indexMatch.first else { continue }
            let index = line.substring(with: i.range)

            let regionsMatch = regionsRegex.matches(in: line,
                                                    options: NSRegularExpression.MatchingOptions(rawValue: 0),
                                                    range: NSRange(location: 0, length: line.count))
            guard regionsMatch.count == 2 else { continue }
            guard let from = regionsMatch.first, let to = regionsMatch.last else { continue }

            let start = line.substring(with: from.range).toDateTime(formatter: Constants.TimeFormatter)
            let end = line.substring(with: to.range).toDateTime(formatter: Constants.TimeFormatter)

            guard let startInterval = start?.timeIntervalSince(Date.referenceDate()) else { continue }
            guard let endInterval = end?.timeIntervalSince(Date.referenceDate()) else { continue }

            let startPosition = to.range.location + to.range.length + 1
            let rangeOfText = NSRange(location: startPosition, length: line.count - startPosition)

            let text = line.substring(with: rangeOfText)
            let plainText = removeStyling(from: text)

            let interval = Interval(index: Int(index)!,
                                    from: startInterval,
                                    to: endInterval,
                                    text: plainText)

            intervals.append(interval)
        }

        return intervals
    }

    // MARK: - Private functions
    private static func removeStyling(from string: String) -> String {
        var result = string.replacingOccurrences(of: "<i>", with: "")
        result = result.replacingOccurrences(of: "</i>", with: "")
        result = result.replacingOccurrences(of: "<br>", with: "")
        result = result.replacingOccurrences(of: "</br>", with: "")
        return result
    }

    // MARK: - Inner types
    enum Constants {
        static let Pattern = "(\\d+)\\n([\\d:,.]+)\\s+-{2}\\>\\s+([\\d:,.]+)\\n([\\s\\S]*?(?=\\n{2,}|$))"
        static let TimeFormatterPattern = "HH:mm:ss.SSS"
        static let TimeFormatter = DateFormatter.defaultDateFormatter(format: Constants.TimeFormatterPattern)
    }

    public struct Interval {
        let index: Int
        let from: Double
        let to: Double
        let text: String
    }
}

private extension String {

    func substring(with nsrange: NSRange) -> String {
        guard let range = Range(nsrange, in: self) else { return "" }
        return String(self[range])
    }
}

private extension Date {

    static func referenceDate() -> Date {
        var components = DateComponents()
        components.year = 2000
        if let zone = TimeZone(identifier: "UTC") {
            components.timeZone = zone
        }
        return Calendar.current.date(from: components)!
    }
}

private extension DateFormatter {

    static func defaultDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        if let zone = TimeZone(identifier: "UTC") {
            formatter.timeZone = zone
        }
        formatter.dateFormat = format
        return formatter
    }
}

private extension String {

    func toDateTime(formatter: DateFormatter) -> Date? {
        if let date = formatter.date(from: self) {
            return date
        }
        return nil
    }
}
