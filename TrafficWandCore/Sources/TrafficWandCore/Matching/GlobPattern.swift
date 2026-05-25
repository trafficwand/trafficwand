import Foundation

/// A wildcard-glob matcher for host strings.
///
/// Glob semantics (locked during planning):
/// - `*` matches zero or more of **any** character, including dots.
/// - `?` matches exactly one character (any character, including a dot).
/// - Every other character is literal; regex metacharacters in the literal
///   portions are escaped, so a literal `.` matches only `.` and `(`, `+`, `$`,
///   etc. are matched literally.
/// - Matching is **case-insensitive** and **anchored** to the full host
///   (`^…$`), so the whole host must match.
///
/// Consequences of full-host anchoring:
/// - `*.github.com` matches `gist.github.com` but **not** the apex `github.com`
///   (the literal leading dot requires at least `something.`).
/// - `*github.com` matches **both** the apex `github.com` and subdomains such as
///   `gist.github.com`.
///
/// The glob is compiled to an `NSRegularExpression` once at initialization and
/// the compiled form is cached for reuse across every `matches(_:)` call.
public struct GlobPattern: Sendable {
    /// The original glob pattern as supplied by the caller.
    public let pattern: String

    /// The compiled, case-insensitive, fully anchored regular expression.
    /// Compiled once at init and reused for every match. `nil` only if the glob
    /// somehow fails to compile, in which case nothing matches.
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        self.pattern = pattern
        self.regex = Self.compile(pattern)
    }

    /// Returns `true` when `host` matches the glob over its entire length.
    public func matches(_ host: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(host.startIndex..<host.endIndex, in: host)
        return regex.firstMatch(in: host, options: [], range: range) != nil
    }

    /// Translates a glob into an anchored, case-insensitive `NSRegularExpression`.
    ///
    /// Literal runs are escaped via `NSRegularExpression.escapedPattern(for:)`
    /// so metacharacters never leak into the regex; `*` becomes `.*` and `?`
    /// becomes `.` (DOTALL is enabled so both span newlines, matching the
    /// "any character" intent even though hosts never contain them).
    private static func compile(_ glob: String) -> NSRegularExpression? {
        var regexBody = ""
        for character in glob {
            switch character {
            case "*":
                regexBody += ".*"
            case "?":
                regexBody += "."
            default:
                regexBody += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        let anchored = "^" + regexBody + "$"
        return try? NSRegularExpression(
            pattern: anchored,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }
}
