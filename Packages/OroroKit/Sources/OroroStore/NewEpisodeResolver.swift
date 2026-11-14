import Foundation
import OroroCore

// STUB (T3) — implemented by Task ST5.
public actor NewEpisodeResolver: NewEpisodeResolving {
    private let details: any DetailProviding
    private let maxPerRun: Int

    public init(details: any DetailProviding, maxPerRun: Int = 10) {
        self.details = details
        self.maxPerRun = maxPerRun
    }

    public func cached() async -> [Int: NewEpisodeInfo] {
        [:]
    }

    public func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] {
        [:]
    }
}
