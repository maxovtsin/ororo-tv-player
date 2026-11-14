import Foundation

/// Scrubbed API recordings from Task T2 (`Fixtures/<name>.json`).
public enum Fixtures {
    /// Raw bytes of `Fixtures/<name>.json`; empty `Data` if the fixture does not exist.
    public static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }
}
