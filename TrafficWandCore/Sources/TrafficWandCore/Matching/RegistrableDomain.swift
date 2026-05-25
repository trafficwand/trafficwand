import Foundation

/// Extracts the *registrable domain* (the eTLD+1 — effective top-level domain
/// plus one label) from a host string.
///
/// Examples: `www.x.com` → `x.com`, `a.b.x.co.uk` → `x.co.uk`.
///
/// ## Limitation: no Public Suffix List
///
/// A fully correct eTLD+1 requires the Mozilla Public Suffix List, which is a
/// large, frequently-changing dataset. To keep Core dependency-free and small,
/// this is a **heuristic**: the default assumption is that the public suffix is
/// the last label (e.g. `com`), and a small embedded set of common *multi-label*
/// public suffixes (`co.uk`, `com.au`, `co.jp`, `org.uk`, …) is recognized so
/// that those resolve to the right eTLD+1. Hosts using a multi-label suffix that
/// is **not** in the embedded set will be under-stripped (treated as a plain
/// single-label TLD), which is acceptable for the "remember this site" feature:
/// the resulting rule is still scoped to a sensible domain, just occasionally
/// slightly narrower or broader than a PSL-perfect result.
///
/// Returns `nil` when the host has no registrable domain: a single-label host
/// (`localhost`), an IP literal (IPv4 or IPv6), an empty string, or a host that
/// is itself only a known public suffix.
public enum RegistrableDomain {
    /// Common multi-label public suffixes. Not exhaustive — see the type doc
    /// comment for the no-Public-Suffix-List limitation.
    private static let multiLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au",
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz",
        "co.za", "org.za", "web.za",
        "com.br", "net.br", "org.br", "gov.br",
        "com.cn", "net.cn", "org.cn", "gov.cn",
        "co.in", "net.in", "org.in", "gen.in", "firm.in", "ind.in",
        "co.kr", "or.kr", "ne.kr", "go.kr",
        "com.mx", "com.sg", "com.hk", "com.tw", "com.tr",
        "co.il", "co.id", "co.th", "com.ar", "com.ua"
    ]

    /// Returns the registrable domain (eTLD+1) of `host`, or `nil` when the host
    /// has no registrable domain (single-label host, IP literal, empty, or a
    /// bare public suffix).
    public static func of(host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // IP literals have no registrable domain.
        if isIPLiteral(trimmed) { return nil }

        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // A registrable domain needs at least two labels (label + TLD).
        guard labels.count >= 2, !labels.contains(where: \.isEmpty) else { return nil }

        // Recognized multi-label public suffix → eTLD+1 has three labels.
        if labels.count >= 2 {
            let lastTwo = labels.suffix(2).joined(separator: ".")
            if multiLabelSuffixes.contains(lastTwo) {
                guard labels.count >= 3 else { return nil }
                return labels.suffix(3).joined(separator: ".")
            }
        }

        // Default: assume a single-label public suffix → eTLD+1 is the last two labels.
        return labels.suffix(2).joined(separator: ".")
    }

    /// Heuristically detects an IP-literal host (IPv4 dotted-quad or any IPv6
    /// address, which contains a colon and never appears in a registrable-domain
    /// context).
    private static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true } // IPv6 (URL.host strips the brackets)
        return isIPv4(host)
    }

    /// Returns `true` when `host` is a dotted-quad IPv4 literal (four 0–255 octets).
    private static func isIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.allSatisfy(\.isNumber), let value = Int(octet) else { return false }
            return (0...255).contains(value)
        }
    }
}
