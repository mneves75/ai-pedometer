import Foundation

@MainActor
enum Formatters {
    private static let stepCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let caloriesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropAll]
        formatter.maximumUnitCount = 2
        formatter.calendar = .autoupdatingCurrent
        return formatter
    }()

    static func stepCountString(_ value: Int) -> String {
        stepCountFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Walking or route distance: meters until the value rounds to 1 km, then kilometers, or miles, as the
    /// region and the Settings > Measurement System preference choose.
    static func distanceString(meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let unit = UnitLength(forLocale: locale, usage: .road)
        // Compared after rounding, so 999.6 m reads "1 km" rather than "1,000 m".
        if unit == .kilometers, meters < 999.5 {
            return lengthString(measurement, maximumFractionDigits: 0, locale: locale)
        }
        return lengthString(measurement.converted(to: unit), maximumFractionDigits: 2, locale: locale)
    }

    /// Elevation gain: meters or feet.
    static func elevationString(meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return lengthString(measurement.converted(to: UnitLength(forLocale: locale, usage: .general)), maximumFractionDigits: 0, locale: locale)
    }

    /// Step length: centimeters or inches.
    static func stepLengthString(meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let unit = UnitLength(forLocale: locale, usage: .person)
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
        return lengthString(measurement, maximumFractionDigits: unit == .centimeters ? 0 : 1, locale: locale)
    }

    static func caloriesString(_ value: Double) -> String {
        caloriesFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func durationString(seconds: TimeInterval) -> String {
        durationFormatter.string(from: max(seconds, 0)) ?? "0m"
    }

    // The unit comes from `UnitLength(forLocale:usage:)`, not `MeasurementFormatter.naturalScale`: iOS keeps
    // the Measurement System preference outside the locale identifier (a US-region phone set to Metric
    // reports `en_US`), and natural scale picked yards and miles from the identifier. `FormatStyle` honors
    // that preference but ignores Settings > Number Format, which `MeasurementFormatter` honors, so the
    // number is formatted here in the provided unit. A formatter per call costs about 0.1 ms, most of it the
    // unit lookup, and needs no invalidation when either setting changes.
    private static func lengthString(
        _ measurement: Measurement<UnitLength>,
        maximumFractionDigits: Int,
        locale: Locale
    ) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: measurement)
    }
}

enum Localization {
    /// Streak length in days, pluralized ("1 day", "2 days"). Shared by the app, watch and widgets.
    ///
    /// Interpolated, not `format(_:)`: `String(format:)` receives the key's `other` form and never applies the
    /// catalog's plural rule, so the watch and widgets rendered "1 days".
    static func streakDays(_ days: Int, locale: Locale? = nil) -> String {
        L10n.localized("\(Int64(days)) days", locale: locale, comment: "Streak length in days")
    }

    /// Weekly widget streak label, "Streak: 1 day". The count is a pluralized `%@` argument because
    /// `format(_:)` drops plural variations.
    static func widgetStreakLabel(_ days: Int, locale: Locale? = nil) -> String {
        String(
            format: L10n.localized(
                "Streak: %@",
                locale: locale,
                comment: "Widget label for streak length; the argument is a pluralized day count such as \"1 day\""
            ),
            locale: locale ?? .autoupdatingCurrent,
            streakDays(days, locale: locale)
        )
    }

    /// Weekly widget accessibility value. `today` and `week` arrive already formatted as counts.
    static func widgetWeeklySummary(
        today: String,
        week: String,
        streakDays days: Int,
        isWheelchair: Bool,
        locale: Locale? = nil
    ) -> String {
        let format = isWheelchair
            ? L10n.localized(
                "%@ pushes today, %@ pushes this week, streak of %@",
                locale: locale,
                comment: "Accessibility value for weekly wheelchair pushes widget; the last argument is a pluralized day count"
            )
            : L10n.localized(
                "%@ steps today, %@ steps this week, streak of %@",
                locale: locale,
                comment: "Accessibility value for weekly steps widget; the last argument is a pluralized day count"
            )
        return String(format: format, locale: locale ?? .autoupdatingCurrent, today, week, streakDays(days, locale: locale))
    }

    static func format(_ key: String.LocalizationValue, comment: StaticString, _ arguments: any CVarArg...) -> String {
        let format = L10n.localized(key, comment: comment)
        return String(format: format, locale: Locale.autoupdatingCurrent, arguments: arguments)
    }
}
