import Foundation

extension String {
    var expandedTildePath: String {
        (self as NSString).expandingTildeInPath
    }

    var abbreviatedTildePath: String {
        (self as NSString).abbreviatingWithTildeInPath
    }

    var jsonEscaped: String {
        var escaped = self.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        return escaped
    }
}
