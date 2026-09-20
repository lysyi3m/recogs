import Foundation

/// Minimal `.env` reader for local development only.
///
/// This lives in the probe executable on purpose: the shipping app reads the token from the
/// Keychain, and an env-var fallback must never ship.
public enum DotEnv {
    /// Walks up from `directory` looking for a `.env` file and parses it.
    public static func load(startingAt directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> [String: String] {
        guard let url = locate(startingAt: directory) else { return [:] }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(contents)
    }

    public static func locate(startingAt directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let candidate = current.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    public static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if key.isEmpty { continue }
            result[key] = value
        }
        return result
    }
}
