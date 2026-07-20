import Foundation
import Darwin

/// Link safety policy for AI-rendered Markdown.
///
/// We intentionally restrict URL schemes to reduce the blast radius of model-generated links.
enum AIChatLinkPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }

        // Reject malformed "http:foo" shapes and credentialed URLs from model output.
        guard let host = url.host, !host.isEmpty else { return false }
        guard url.user == nil, url.password == nil else { return false }
        guard !isLocalHost(host) else { return false }
        guard !isObfuscatedNumericHost(host) else { return false }
        guard !isLiteralIPAddress(host) else { return false }

        return true
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = normalizeHost(host)
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
            || normalized.hasSuffix(".local")
            || normalized.hasSuffix(".internal")
            || normalized.hasSuffix(".lan")
            || normalized.hasSuffix(".home")
            || normalized.hasSuffix(".home.arpa")
    }

    private static func isObfuscatedNumericHost(_ host: String) -> Bool {
        let normalized = normalizeHost(host)

        if normalized.hasPrefix("0x") {
            return true
        }

        let allowed = CharacterSet(charactersIn: "0123456789.")
        let isNumericLike = normalized.unicodeScalars.allSatisfy { allowed.contains($0) }
        guard isNumericLike else { return false }

        // Numeric-like host that is not strict dotted-decimal is parser-dependent
        // (e.g. 2130706433, 127.1, 0x7f000001) and can resolve to loopback.
        return parseIPv4Octets(normalized) == nil
    }

    private static func isLiteralIPAddress(_ host: String) -> Bool {
        let normalized = normalizeHost(host)

        if parseIPv4Octets(normalized) != nil {
            return true
        }

        var addr6 = in6_addr()
        let ipv6WithoutZone = normalized.split(separator: "%", maxSplits: 1).first.map(String.init) ?? normalized
        return ipv6WithoutZone.withCString { inet_pton(AF_INET6, $0, &addr6) } == 1
    }

    private static func parseIPv4Octets(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        for part in parts {
            guard !part.isEmpty else { return nil }
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            // Reject ambiguous forms that some parsers interpret as octal.
            guard !(part.count > 1 && part.first == "0") else { return nil }
            guard let value = UInt8(part) else { return nil }
            octets.append(value)
        }

        return (octets[0], octets[1], octets[2], octets[3])
    }

    private static func normalizeHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}

struct AIChatPendingLink: Equatable {
    let url: URL
    let host: String
}

struct AIChatLinkConfirmation {
    private(set) var pendingLink: AIChatPendingLink?

    @discardableResult
    mutating func request(_ url: URL) -> Bool {
        guard AIChatLinkPolicy.isAllowed(url), let host = url.host else {
            pendingLink = nil
            return false
        }

        pendingLink = AIChatPendingLink(
            url: url,
            host: host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        )
        return true
    }

    mutating func confirm() -> URL? {
        defer { pendingLink = nil }
        return pendingLink?.url
    }

    mutating func cancel() {
        pendingLink = nil
    }
}
