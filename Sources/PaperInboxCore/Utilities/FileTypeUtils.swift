import Foundation

public enum FileTypeUtils {
    public static func titleFromPDFURL(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func titleFromSourceURL(_ url: URL) -> String {
        var pieces: [String] = []

        if let host = url.host, !host.isEmpty {
            pieces.append(host)
        }

        let path = url.path
            .split(separator: "/")
            .last
            .map(String.init)?
            .removingPercentEncoding

        if let path, !path.isEmpty {
            pieces.append(path)
        }

        return pieces.isEmpty ? url.absoluteString : pieces.joined(separator: " / ")
    }
}
