import Foundation

@MainActor
enum Formatters {
    private static let stepCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let distanceFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.unitOptions = .naturalScale
        return formatter
    }()

    private static let caloriesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropAll]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static func stepCountString(_ value: Int) -> String {
        stepCountFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func distanceString(meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return distanceFormatter.string(from: measurement)
    }

    static func caloriesString(_ value: Double) -> String {
        caloriesFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func durationString(seconds: TimeInterval) -> String {
        durationFormatter.string(from: max(seconds, 0)) ?? "0m"
    }
}

enum Localization {
    static func format(_ key: String.LocalizationValue, comment: StaticString, _ arguments: any CVarArg...) -> String {
        let format = String(localized: key, comment: comment)
        return String(format: format, locale: .current, arguments: arguments)
    }
}
