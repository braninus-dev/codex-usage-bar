import Foundation
import CoreFoundation

public enum QuotaWindowKind: String, CaseIterable, Codable, Sendable {
    case primary
    case secondary
}

public struct UsageWindow: Sendable {
    public let usedPercent: Double
    public let minutes: Int?
    public let resetsAt: TimeInterval?

    public var isExhausted: Bool { usedPercent >= 100 }
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    public var remainingText: String {
        if isExhausted { return "0%" }
        if remainingPercent < 1 { return "<1%" }
        return "\(Int(remainingPercent.rounded(.down)))%"
    }
    public var label: String {
        guard let minutes else { return "额度" }
        if minutes >= 1440 { return "\(minutes / 1440) 天额度" }
        if minutes >= 60 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }

    private static func optionalInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let numberValue = number.doubleValue
        guard numberValue.isFinite,
              numberValue.rounded(.towardZero) == numberValue,
              numberValue >= Double(Int.min), numberValue < Double(Int.max) else { return nil }
        return number.intValue
    }

    private static func optionalNumber(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    public init?(json: Any?) {
        guard let object = json as? [String: Any],
              let number = object["usedPercent"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0 else { return nil }
        usedPercent = value
        minutes = Self.optionalInteger(object["windowDurationMins"])
        resetsAt = Self.optionalNumber(object["resetsAt"])
    }
}

public struct UsageSnapshot: Sendable {
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let accountID: String?
    public let ordinaryUsageAllowed: Bool?
    public let spendControlReached: Bool?
    public let rateLimitReachedType: String?
    public let fetchedAt: Date
    public let receivedUptime: TimeInterval

    public init?(
        _ result: [String: Any],
        fetchedAt: Date = Date(),
        receivedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        let bucket: [String: Any]?
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any], !buckets.isEmpty {
            // Never substitute another model's bucket for the standard Codex quota.
            bucket = buckets["codex"] as? [String: Any]
        } else {
            bucket = result["rateLimits"] as? [String: Any]
        }
        guard let bucket else { return nil }
        primary = UsageWindow(json: bucket["primary"])
        secondary = UsageWindow(json: bucket["secondary"])
        accountID = (result["accountId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ordinaryUsageAllowed = Self.optionalBoolean(result["ordinaryUsageAllowed"])
        spendControlReached = Self.optionalBoolean(result["spendControlReached"])
        rateLimitReachedType = (result["rateLimitReachedType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.fetchedAt = fetchedAt
        self.receivedUptime = receivedUptime
    }

    public func window(_ kind: QuotaWindowKind) -> UsageWindow? {
        kind == .primary ? primary : secondary
    }

    private static func optionalBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        // JSON booleans are NSNumber values too; reject numeric 0/1 unless the
        // Foundation object is actually tagged as a boolean.
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
