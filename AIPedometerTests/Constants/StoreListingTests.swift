import Foundation
import Testing

@testable import AIPedometer

/// Contract of the App Store listing in `store/app-store/` (`asc metadata` format). The listing is
/// read for the app's own marketing version, so a version bump without a listing fails here.
struct StoreListingTests {
    private struct AppInfo: Decodable {
        let name: String
        let subtitle: String
        let privacyPolicyUrl: String
    }

    private struct VersionInfo: Decodable {
        let description: String
        let keywords: String
        let promotionalText: String
        let supportUrl: String
    }

    private struct Pricing: Decodable {
        let appId: String
        let baseTerritory: String
        let currency: String
        let customerPrice: String
        let pricePointId: String
    }

    private static let locales = ["en-US", "pt-BR"]

    private static let storeRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("store/app-store")

    private static func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        let data = try Data(contentsOf: storeRoot.appendingPathComponent(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func versionInfo(_ locale: String) throws -> VersionInfo {
        let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        return try load(VersionInfo.self, "version/\(version)/\(locale).json")
    }

    /// App Review compares the in-app Privacy Policy link with the listing's (Guideline 5.1.1(i)).
    @Test(arguments: [("en-US", "en"), ("pt-BR", "pt-BR")])
    func inAppLinksMatchTheListing(storeLocale: String, languageCode: String) throws {
        let appInfo = try Self.load(AppInfo.self, "app-info/\(storeLocale).json")
        let versionInfo = try Self.versionInfo(storeLocale)

        #expect(AppConstants.Links.privacyPolicy(languageCode: languageCode)?.absoluteString == appInfo.privacyPolicyUrl)
        #expect(AppConstants.Links.support(languageCode: languageCode)?.absoluteString == versionInfo.supportUrl)
    }

    @Test(arguments: ["en", "en-US", "es-ES", "pt-PT", "fr"])
    func languagesOtherThanPtBROpenTheEnglishPages(languageCode: String) {
        #expect(AppConstants.Links.privacyPolicy(languageCode: languageCode) == AppConstants.Links.privacyPolicy(languageCode: "en"))
        #expect(AppConstants.Links.support(languageCode: languageCode) == AppConstants.Links.support(languageCode: "en"))
    }

    @Test
    func defaultLinksFollowTheAppLanguage() {
        #expect(AppConstants.Links.privacyPolicy == AppConstants.Links.privacyPolicy(languageCode: AppLanguage.defaultLanguageCode))
        #expect(AppConstants.Links.support == AppConstants.Links.support(languageCode: AppLanguage.defaultLanguageCode))
    }

    /// App Store Connect field limits, and the Terms of Use link a subscription app needs in its
    /// description (Guideline 3.1.2).
    @Test(arguments: locales)
    func listingFitsAppStoreConnectLimits(locale: String) throws {
        let appInfo = try Self.load(AppInfo.self, "app-info/\(locale).json")
        let versionInfo = try Self.versionInfo(locale)

        #expect(appInfo.name == "AIPedometer")
        #expect((1...30).contains(appInfo.subtitle.count))
        #expect((1...100).contains(versionInfo.keywords.count))
        #expect((1...170).contains(versionInfo.promotionalText.count))
        #expect((1...4000).contains(versionInfo.description.count))
        #expect(versionInfo.description.contains(try #require(AppConstants.Links.termsOfUse).absoluteString))
    }

    /// Paid download at R$ 1,99 in the Brazil base territory, like the studio's other paid apps.
    @Test
    func priceIsOneNinetyNineReais() throws {
        let pricing = try Self.load(Pricing.self, "pricing.json")

        #expect(pricing.appId == "6778799265")
        #expect(pricing.baseTerritory == "BRA")
        #expect(pricing.currency == "BRL")
        #expect(pricing.customerPrice == "1.99")

        // The price point id is base64 JSON naming this app and territory; a point copied from
        // another app would be rejected by App Store Connect.
        let padded = pricing.pricePointId.padding(
            toLength: (pricing.pricePointId.count + 3) / 4 * 4, withPad: "=", startingAt: 0
        )
        let decoded = try JSONDecoder().decode(
            [String: String].self, from: try #require(Data(base64Encoded: padded))
        )
        #expect(decoded["s"] == pricing.appId)
        #expect(decoded["t"] == pricing.baseTerritory)
    }
}
