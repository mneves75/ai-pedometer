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
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[fe80::1%25en0]")!))
    }

    @Test("Rejects public literal IPs")
    func rejectsPublicLiteralIPs() {
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://8.8.8.8")!))
        #expect(!AIChatLinkPolicy.isAllowed(URL(string: "https://[2606:4700:4700::1111]")!))
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

@Suite("AIChatLinkConfirmation Tests")
struct AIChatLinkConfirmationTests {
    @Test("An allowed model link requires confirmation before yielding a URL")
    func allowedLinkRequiresConfirmation() {
        let url = URL(string: "https://EXAMPLE.com/path?query=value")!
        var confirmation = AIChatLinkConfirmation()

        let requiresConfirmation = confirmation.request(url)

        #expect(requiresConfirmation)
        #expect(confirmation.pendingLink?.url == url)
        #expect(confirmation.pendingLink?.host == "example.com")

        let confirmedURL = confirmation.confirm()
        #expect(confirmedURL == url)
        #expect(confirmation.pendingLink == nil)
        let repeatedConfirmation = confirmation.confirm()
        #expect(repeatedConfirmation == nil)
    }

    @Test("A rejected model link never becomes confirmable")
    func rejectedLinkNeverBecomesConfirmable() {
        var confirmation = AIChatLinkConfirmation()

        let requiresConfirmation = confirmation.request(URL(string: "file:///etc/hosts")!)

        #expect(!requiresConfirmation)
        #expect(confirmation.pendingLink == nil)
        let confirmedURL = confirmation.confirm()
        #expect(confirmedURL == nil)
    }

    @Test("Cancelling clears the pending model link")
    func cancellingClearsPendingLink() {
        var confirmation = AIChatLinkConfirmation()

        let requiresConfirmation = confirmation.request(URL(string: "https://example.com/path")!)
        #expect(requiresConfirmation)
        confirmation.cancel()

        #expect(confirmation.pendingLink == nil)
        let confirmedURL = confirmation.confirm()
        #expect(confirmedURL == nil)
    }
}

@Suite("AI Coach Bottom Pinning Policy Tests")
struct AICoachBottomPinningPolicyTests {
    @Test("Pinning follows actual bottom visibility")
    func pinningFollowsBottomVisibility() {
        #expect(
            AICoachBottomPinningPolicy.isBottomVisible(
                contentOffsetY: 300,
                contentHeight: 700,
                containerHeight: 400,
                bottomInset: 0
            )
        )
        #expect(
            !AICoachBottomPinningPolicy.isBottomVisible(
                contentOffsetY: 250,
                contentHeight: 700,
                containerHeight: 400,
                bottomInset: 0
            )
        )
    }

    @Test("Returning within the bottom tolerance restores follow mode")
    func bottomToleranceRestoresFollowMode() {
        #expect(
            AICoachBottomPinningPolicy.isBottomVisible(
                contentOffsetY: 280,
                contentHeight: 700,
                containerHeight: 400,
                bottomInset: 0
            )
        )
    }

    @Test("Stream growth preserves follow mode until the user scrolls")
    func streamedGrowthDoesNotDisableFollowMode() {
        let afterContentGrowth = AICoachBottomPinningPolicy.updatedPinning(
            currentPinning: true,
            isBottomVisible: false,
            isUserScrollActive: false
        )
        #expect(afterContentGrowth)

        let afterUserScrollsAway = AICoachBottomPinningPolicy.updatedPinning(
            currentPinning: afterContentGrowth,
            isBottomVisible: false,
            isUserScrollActive: true
        )
        #expect(!afterUserScrollsAway)

        let afterUserReturnsToBottom = AICoachBottomPinningPolicy.updatedPinning(
            currentPinning: afterUserScrollsAway,
            isBottomVisible: true,
            isUserScrollActive: true
        )
        #expect(afterUserReturnsToBottom)
    }
}
