import Foundation
import Testing

@testable import AIPedometer

/// Guards the badge award-path invariant: any badge type presented to the user as earnable must
/// have a matching `BadgeDefinition` (title/description/threshold) so the evaluation code can
/// actually unlock it. The original defect was that `distance5km`/`distance10km`/`distanceMarathon`
/// were rendered in the grid but absent from `BadgeDefinitions.all`, so they could never be earned.
@Suite("BadgeDefinitions")
struct BadgeDefinitionsTests {
    /// Categories whose badges have a live award path in `StepTrackingService.evaluateBadges`.
    /// `.challenge` is intentionally excluded — there is no challenge system to complete yet, and
    /// `BadgesView` hides it, so it must not be advertised as earnable.
    private static let awardableCategories: Set<BadgeCategory> = [.steps, .streak, .distance]

    @Test("Every awardable badge type has a definition")
    func everyAwardableBadgeTypeHasDefinition() {
        let definedTypes = Set(BadgeDefinitions.all.map(\.type))
        for type in BadgeType.allCases where Self.awardableCategories.contains(type.category) {
            #expect(
                definedTypes.contains(type),
                "Awardable badge \(type.rawValue) is missing a BadgeDefinition and can never be earned"
            )
        }
    }

    @Test("Distance badges are defined with meter thresholds")
    func distanceBadgesDefinedWithMeterThresholds() {
        let byType = Dictionary(uniqueKeysWithValues: BadgeDefinitions.all.map { ($0.type, $0) })
        #expect(byType[.distance5km]?.requiredValue == 5_000)
        #expect(byType[.distance10km]?.requiredValue == 10_000)
        #expect(byType[.distanceMarathon]?.requiredValue == 42_195)
    }

    @Test("Challenge badge has no award path")
    func challengeBadgeHasNoDefinition() {
        // Documents the deliberate exclusion: adding a definition here without also building a
        // challenge system would re-introduce an unearnable badge in a different place.
        let definedTypes = Set(BadgeDefinitions.all.map(\.type))
        #expect(definedTypes.contains(.monthlyChallenge) == false)
    }

    @Test("Marathon threshold stays within 32-bit Int range for watchOS")
    func marathonThresholdFitsIn32Bit() {
        // Shared/ compiles into the watchOS arm64_32 slice where Int is 32-bit. Every distance
        // threshold must fit in Int32 to avoid an overflow that only surfaces on the watch build.
        for definition in BadgeDefinitions.all where definition.type.category == .distance {
            #expect(definition.requiredValue <= Int(Int32.max))
        }
    }
}
