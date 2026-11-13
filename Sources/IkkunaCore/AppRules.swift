import Foundation

/// Pure shortcut policy, shared by the popup and the keyboard routing path.
public enum AppRules {
    public static func initial(_ name: String) -> String {
        let first = String(name.prefix(1)).lowercased()
        return first.range(of: "^[a-z0-9]$", options: .regularExpression) == nil ? "tab" : first
    }
    public static func shortcut(name: String, bundleID: String, mappings: [String: String], ignored: [String]) -> String? {
        let name = name.lowercased(), bundle = bundleID.lowercased()
        if let mapped = mappings[bundle] ?? mappings[name] { return mapped }
        guard !ignored.contains(bundle), !ignored.contains(name) else { return nil }
        let key = initial(name)
        return key == "tab" || mappings.values.contains(key) ? nil : key
    }
    public static func nextIndex(ids: [String], current: String?) -> Int? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return 0 }
        return (index+1) % ids.count
    }
}
