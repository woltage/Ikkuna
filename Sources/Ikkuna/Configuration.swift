import Foundation
import os

let log = Logger(subsystem: "fi.iiro.Ikkuna", category: "app")

struct Configuration: Codable {
    var windowGap: Double = 4
    var stageManagerLeftInset: Double = 160
    var stageManagerRightInset: Double = 360
    var appKeys: [String: String] = ["com.apple.finder": "0"]
    var ignoredApps: [String] = ["Finder"]
    var captureBundleIDs = ["com.apple.ScreenSharing", "com.parallels.macvm", "com.parallels.desktop.console"]
    var parallelsExcludedTitles = ["Control Center", "Preferences", "About Parallels"]

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ikkuna", isDirectory: true)
    static let url = directory.appendingPathComponent("config.json")

    static func load() throws -> Configuration {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if !FileManager.default.fileExists(atPath: url.path) {
            try encoder.encode(Configuration()).write(to: url, options: .atomic)
        }
        // Merge omitted keys with defaults, while rejecting misspelled settings.
        let defaults = try JSONSerialization.jsonObject(with: encoder.encode(Configuration())) as! [String: Any]
        guard let input = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw ConfigError.invalid("Asetusten pitää olla JSON-objekti.")
        }
        for key in input.keys where defaults[key] == nil { throw ConfigError.invalid("Tuntematon asetus: \(key)") }
        let merged = defaults.merging(input) { _, new in new }
        var result = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: merged))
        for value in [result.windowGap, result.stageManagerLeftInset, result.stageManagerRightInset] {
            guard value.isFinite && value >= 0 else { throw ConfigError.invalid("Välien pitää olla äärellisiä ja vähintään nolla.") }
        }
        var normalized: [String: String] = [:]
        for (name, key) in result.appKeys {
            let key = key.lowercased()
            guard key.count == 1, key.range(of: "^[a-z0-9]$", options: .regularExpression) != nil else {
                throw ConfigError.invalid("Sovellusnäppäimen pitää olla kirjain a–z tai numero: \(name)")
            }
            normalized[name.lowercased()] = key
        }
        result.appKeys = normalized
        result.ignoredApps = result.ignoredApps.map { $0.lowercased() }
        return result
    }
}

enum ConfigError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

func saveJSON<T: Encodable>(_ value: T, name: String) {
    do {
        try FileManager.default.createDirectory(at: Configuration.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: Configuration.directory.appendingPathComponent(name), options: .atomic)
    } catch { log.error("Tallennus epäonnistui: \(error.localizedDescription, privacy: .public)") }
}

func loadJSON<T: Decodable>(_ type: T.Type, name: String) -> T? {
    guard let data = try? Data(contentsOf: Configuration.directory.appendingPathComponent(name)) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}
