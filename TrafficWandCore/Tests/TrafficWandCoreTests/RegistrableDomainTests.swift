import Foundation
import Testing
@testable import TrafficWandCore

@Suite("RegistrableDomain.of(host:)")
struct RegistrableDomainTests {
    @Test("Strips a single subdomain label")
    func stripsSingleSubdomain() {
        #expect(RegistrableDomain.of(host: "www.x.com") == "x.com")
    }

    @Test("Strips a non-www subdomain label")
    func stripsNonWWWSubdomain() {
        #expect(RegistrableDomain.of(host: "news.x.com") == "x.com")
    }

    @Test("Strips multiple subdomain labels")
    func stripsMultipleSubdomains() {
        #expect(RegistrableDomain.of(host: "a.b.news.example.com") == "example.com")
    }

    @Test("Keeps an embedded two-level public suffix (co.uk)")
    func keepsCoUkSuffix() {
        #expect(RegistrableDomain.of(host: "a.b.x.co.uk") == "x.co.uk")
    }

    @Test("Bare two-level public-suffix domain is returned as-is")
    func bareCoUkDomain() {
        #expect(RegistrableDomain.of(host: "x.co.uk") == "x.co.uk")
    }

    @Test("Other embedded two-level suffixes are honored", arguments: [
        ("shop.example.com.au", "example.com.au"),
        ("www.example.co.jp", "example.co.jp"),
        ("a.example.org.uk", "example.org.uk"),
        ("b.example.co.nz", "example.co.nz")
    ])
    func keepsOtherTwoLevelSuffixes(host: String, expected: String) {
        #expect(RegistrableDomain.of(host: host) == expected)
    }

    @Test("Bare apex domain is returned unchanged")
    func bareApexDomain() {
        #expect(RegistrableDomain.of(host: "x.com") == "x.com")
    }

    @Test("Host is lowercased before extraction")
    func lowercasesHost() {
        #expect(RegistrableDomain.of(host: "WWW.X.COM") == "x.com")
    }

    @Test("Single-label host yields nil")
    func singleLabelHostNil() {
        #expect(RegistrableDomain.of(host: "localhost") == nil)
    }

    @Test("IPv4 literal yields nil")
    func ipv4LiteralNil() {
        #expect(RegistrableDomain.of(host: "192.168.0.1") == nil)
    }

    @Test("IPv6 literal yields nil")
    func ipv6LiteralNil() {
        #expect(RegistrableDomain.of(host: "::1") == nil)
        #expect(RegistrableDomain.of(host: "2001:db8::1") == nil)
    }

    @Test("Empty host yields nil")
    func emptyHostNil() {
        #expect(RegistrableDomain.of(host: "") == nil)
    }

    @Test("A bare two-level public suffix alone yields nil")
    func bareSuffixOnlyNil() {
        // "co.uk" is only a suffix with no registrable label in front of it.
        #expect(RegistrableDomain.of(host: "co.uk") == nil)
    }
}
