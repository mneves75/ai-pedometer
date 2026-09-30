import Testing

@testable import AIPedometer

@Suite("ProgressClamp Tests")
struct ProgressClampTests {
    @Test("Finite progress percentages stay representable on all supported architectures")
    func finitePercentagesStayRepresentable() {
        #expect(ProgressClamp.percent(100_000_000) == Int(HealthCount.maximum))
        #expect(ProgressClamp.percent(.greatestFiniteMagnitude) == Int(HealthCount.maximum))
    }

    @Test("Clamps values into unit interval")
    func clampsValuesIntoUnitInterval() {
        #expect(ProgressClamp.unitInterval(-0.1) == 0)
        #expect(ProgressClamp.unitInterval(0) == 0)
        #expect(ProgressClamp.unitInterval(0.5) == 0.5)
        #expect(ProgressClamp.unitInterval(1) == 1)
        #expect(ProgressClamp.unitInterval(1.2) == 1)
    }

    @Test("Clamps non-finite values to zero")
    func clampsNonFiniteValuesToZero() {
        #expect(ProgressClamp.unitInterval(.nan) == 0)
        #expect(ProgressClamp.unitInterval(.infinity) == 0)
        #expect(ProgressClamp.unitInterval(-.infinity) == 0)
    }

    @Test("Converts progress to percentage")
    func convertsProgressToPercentage() {
        #expect(ProgressClamp.percent(-0.2) == 0)
        #expect(ProgressClamp.percent(0) == 0)
        #expect(ProgressClamp.percent(0.25) == 25)
        #expect(ProgressClamp.percent(0.999) == 99)
        #expect(ProgressClamp.percent(1) == 100)
        #expect(ProgressClamp.percent(1.35) == 135)
    }

    @Test("Percent handles non-finite values as zero")
    func percentHandlesNonFiniteValues() {
        #expect(ProgressClamp.percent(.nan) == 0)
        #expect(ProgressClamp.percent(.infinity) == 0)
        #expect(ProgressClamp.percent(-.infinity) == 0)
    }
}
