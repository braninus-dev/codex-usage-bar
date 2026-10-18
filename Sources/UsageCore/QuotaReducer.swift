import Foundation

public enum QuotaAvailability: Equatable, Sendable {
    case available
    case limited
    case unknown
    case confirming
    case restricted
    case unavailable
}

/// Stable state codes; presentation layers translate these for the selected UI language.
public enum QuotaReason: String, Codable, Sendable {
    case connectionLost
    case noSnapshot
    case staleSnapshot
    case bothWindowsRequired
    case accountUnknown
    case otherRestriction
    case permissionUnknown
    case bothWindowsAvailable
    case resetAwaitingConfirmation
    case atLeastOneWindowExhausted
}

public struct QuotaDecision: Sendable {
    public let availability: QuotaAvailability
    public let canResume: Bool
    public let reason: QuotaReason
    public let countdownDeadline: TimeInterval?
    public let displayWindow: QuotaWindowKind?
}

/// The single source of truth for quota availability and the battery display.
public enum QuotaReducer {
    public static let expectedPrimaryMinutes = 300
    public static let expectedSecondaryMinutes = 10_080
    public static let freshnessBudget: TimeInterval = 90

    public static func reduce(
        snapshot: UsageSnapshot?,
        now: TimeInterval,
        monotonicNow: TimeInterval,
        connected: Bool = true,
        preferredWindow: QuotaWindowKind = .primary
    ) -> QuotaDecision {
        guard connected else { return decision(.unknown, .connectionLost) }
        guard let snapshot else { return decision(.unavailable, .noSnapshot) }

        let age = monotonicNow - snapshot.receivedUptime
        guard age >= 0, age <= freshnessBudget else {
            return decision(.unknown, .staleSnapshot)
        }

        let primary = snapshot.primary.flatMap { $0.minutes == expectedPrimaryMinutes ? $0 : nil }
        let secondary = snapshot.secondary.flatMap { $0.minutes == expectedSecondaryMinutes ? $0 : nil }
        let knownWindows = [primary, secondary].compactMap { $0 }
        let exhausted = knownWindows.filter(\.isExhausted)
        let deadline = combinedDeadline(exhausted, now: now)
        let exhaustedDisplay = displayKind(primary: primary, secondary: secondary, preferred: preferredWindow)

        guard primary != nil, secondary != nil else {
            return decision(.unknown, .bothWindowsRequired, windows: knownWindows, now: now, displayWindow: exhaustedDisplay)
        }
        guard let accountID = snapshot.accountID, !accountID.isEmpty else {
            return decision(.unknown, .accountUnknown, windows: knownWindows, now: now, displayWindow: exhaustedDisplay)
        }

        if snapshot.spendControlReached == true || snapshot.rateLimitReachedType != nil || snapshot.ordinaryUsageAllowed == false {
            return decision(.restricted, .otherRestriction, windows: knownWindows, now: now, displayWindow: exhaustedDisplay)
        }
        guard snapshot.ordinaryUsageAllowed == true else {
            return decision(.unknown, .permissionUnknown, windows: knownWindows, now: now, displayWindow: exhaustedDisplay)
        }
        guard !exhausted.isEmpty else {
            return QuotaDecision(availability: .available, canResume: true, reason: .bothWindowsAvailable, countdownDeadline: nil, displayWindow: preferredWindow)
        }

        if exhausted.contains(where: { ($0.resetsAt ?? .infinity) <= now }) {
            return QuotaDecision(availability: .confirming, canResume: false, reason: .resetAwaitingConfirmation, countdownDeadline: deadline, displayWindow: exhaustedDisplay)
        }
        return QuotaDecision(availability: .limited, canResume: false, reason: .atLeastOneWindowExhausted, countdownDeadline: deadline, displayWindow: exhaustedDisplay)
    }

    private static func decision(
        _ availability: QuotaAvailability,
        _ reason: QuotaReason,
        windows: [UsageWindow] = [],
        now: TimeInterval = 0,
        displayWindow: QuotaWindowKind? = nil
    ) -> QuotaDecision {
        QuotaDecision(availability: availability, canResume: false, reason: reason, countdownDeadline: combinedDeadline(windows.filter(\.isExhausted), now: now), displayWindow: displayWindow)
    }

    private static func combinedDeadline(_ windows: [UsageWindow], now: TimeInterval) -> TimeInterval? {
        guard !windows.isEmpty,
              windows.allSatisfy({ $0.resetsAt?.isFinite == true }) else { return nil }
        return windows.compactMap(\.resetsAt).max().map { max(now, $0) }
    }

    private static func displayKind(primary: UsageWindow?, secondary: UsageWindow?, preferred: QuotaWindowKind) -> QuotaWindowKind? {
        let primaryExhausted = primary?.isExhausted == true
        let secondaryExhausted = secondary?.isExhausted == true
        switch (primaryExhausted, secondaryExhausted) {
        case (true, false): return .primary
        case (false, true): return .secondary
        case (true, true):
            guard let p = primary?.resetsAt, let s = secondary?.resetsAt else { return nil }
            if p == s { return preferred }
            return p > s ? .primary : .secondary
        case (false, false): return nil
        }
    }
}
