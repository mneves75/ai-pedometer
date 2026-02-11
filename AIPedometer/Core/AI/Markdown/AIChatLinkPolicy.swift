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
        guard !isLiteralPrivateIPAddress(host) else { return false }

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

    private static func isLiteralPrivateIPAddress(_ host: String) -> Bool {
        let normalized = normalizeHost(host)

        if let ipv4 = parseIPv4Octets(normalized) {
            let a = ipv4.0
            let b = ipv4.1
            let c = ipv4.2
            let d = ipv4.3
            return isNonPublicIPv4(a: a, b: b, c: c, d: d)
        }

        var addr6 = in6_addr()
        if normalized.withCString({ inet_pton(AF_INET6, $0, &addr6) }) == 1 {
            var bytes = [UInt8](repeating: 0, count: 16)
            withUnsafeBytes(of: &addr6) { rawBuffer in
                bytes.withUnsafeMutableBytes { mutable in
                    mutable.copyMemory(from: rawBuffer)
                }
            }

            let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
            let isUnspecified = bytes.allSatisfy { $0 == 0 }
            let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc      // fc00::/7
            let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 // fe80::/10
            let isMulticast = bytes[0] == 0xff // ff00::/8
            let isDocumentation = bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 // 2001:db8::/32

            let isIPv4Mapped =
                bytes[0..<10].allSatisfy { $0 == 0 } &&
                bytes[10] == 0xff &&
                bytes[11] == 0xff
            if isIPv4Mapped {
                return isNonPublicIPv4(a: bytes[12], b: bytes[13], c: bytes[14], d: bytes[15])
            }

            return isLoopback || isUnspecified || isUniqueLocal || isLinkLocal || isMulticast || isDocumentation
        }

        return false
    }

    private static func isNonPublicIPv4(a: UInt8, b: UInt8, c: UInt8, d: UInt8) -> Bool {
        _ = c
        _ = d
        return a == 10
            || a == 127
            || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168)
            || (a == 169 && b == 254)
            || (a == 100 && (64...127).contains(b))  // 100.64.0.0/10 CGNAT
            || (a == 198 && (b == 18 || b == 19))    // 198.18.0.0/15 benchmarking
            || a == 0
            || a >= 224 // multicast (224/4) + reserved/broadcast (240/4)
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
