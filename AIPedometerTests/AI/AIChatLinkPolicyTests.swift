import Foundation
import Testing

@testable import AIPedometer

@Suite("AIChatLinkPolicy Tests")
struct AIChatLinkPolicyTests {
    @Test("Allows only http/https URL schemes")
    func allowsOnlyHttpSchemes() {
        #expect(AIChatLinkPolicy.isAllowed(URL(string: "https://example.com")!))
        #expect(AIChatLinkPolicy.isAllowed(URL(string: "http://example.com")!))
        #expect(AIChatLinkPolicy.isAllowed(URL(string: "HTTPS://example.com")!))

        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "file:///etc/hosts")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "tel:123")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "mailto:test@example.com")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "data:text/plain,hello")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "javascript:alert(1)")!))
    }

    @Test("Rejects URLs without scheme")
    func rejectsSchemeLessURLs() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "/relative/path")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "example.com/path")!))
    }

    @Test("Rejects malformed http(s) URLs without host")
    func rejectsHttpWithoutHost() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "http:javascript:alert(1)")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https:/broken.example.com")!))
    }

    @Test("Rejects credentialed URLs from model output")
    func rejectsCredentialedURLs() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://user@example.com")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://user:pass@example.com")!))
    }

    @Test("Rejects loopback and local network hostnames")
    func rejectsLocalHosts() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://localhost/path")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "http://127.0.0.1:3000")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[::1]/")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://my-mac.local")!))
    }

    @Test("Rejects private and link-local literal IPs")
    func rejectsPrivateLiteralIPs() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://10.0.0.4")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://172.20.10.2")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://192.168.1.50")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://169.254.1.2")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://100.64.0.1")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://198.18.0.1")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://224.0.0.1")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://255.255.255.255")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[fe80::1]")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[fc00::abcd]")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[ff02::1]")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[2001:db8::1]")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[::ffff:10.0.0.1]")!))
    }

    @Test("Allows public literal IPs when scheme is valid")
    func allowsPublicLiteralIPs() {
        #expect(AIChatLinkPolicy.isAllowed(URL(string: "https://8.8.8.8")!))
        #expect(AIChatLinkPolicy.isAllowed(URL(string: "https://[2606:4700:4700::1111]")!))
    }

    @Test("Rejects internal hostname suffixes")
    func rejectsInternalHostSuffixes() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://api.internal")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://router.lan")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://hub.home")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://tv.home.arpa")!))
    }

    @Test("Rejects obfuscated numeric host forms")
    func rejectsObfuscatedNumericHosts() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://2130706433")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://127.1")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://0x7f000001")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://0177.0.0.1")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://localhost.")!))
    }
}
