import Foundation
import CryptoKit
import Darwin

public struct ConfirmedResetEvent: Codable, Equatable, Identifiable, Sendable {
    public let window: QuotaWindowKind
    public let durationMinutes: Int
    public let previousResetAt: TimeInterval
    public let newResetAt: TimeInterval
    public let detectedAt: Date
    fileprivate let dedupeKey: String

    public var id: String { dedupeKey }

    public init(id: String, window: QuotaWindowKind, durationMinutes: Int, previousResetAt: TimeInterval, newResetAt: TimeInterval, detectedAt: Date) {
        self.window = window
        self.durationMinutes = durationMinutes
        self.previousResetAt = previousResetAt
        self.newResetAt = newResetAt
        self.detectedAt = detectedAt
        self.dedupeKey = id
    }
}

private struct ResetBaseline: Codable, Equatable {
    var accountDigest: String
    var primaryResetAt: TimeInterval
    var secondaryResetAt: TimeInterval
    var primaryWasExhausted: Bool?
    var secondaryWasExhausted: Bool?
}

private struct ResetTrackerDocument: Codable {
    var version: Int
    var baseline: ResetBaseline?
    var pendingEvents: [ConfirmedResetEvent]
    var deliveredKeys: [String]
}

/// Confirms only observed period-boundary advances. It does not infer resets from time or usage drops alone.
public struct ResetTracker {
    public static let currentVersion = 1
    public let fileURL: URL
    private let accountSalt: String
    private var document = ResetTrackerDocument(version: currentVersion, baseline: nil, pendingEvents: [], deliveredKeys: [])

    public init(fileURL: URL, accountSalt: String) {
        self.fileURL = fileURL
        self.accountSalt = accountSalt
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("local.codex.usage-bar", isDirectory: true).appendingPathComponent("quota-resets.json")
    }

    public mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ResetTrackerDocument.self, from: data)
        guard decoded.version == Self.currentVersion else { throw IdeaStoreError.unsupportedVersion(decoded.version) }
        document = decoded
    }

    /// Establishes a baseline on first launch/account switch. Repeated snapshots for one boundary never emit again.
    public mutating func observe(_ snapshot: UsageSnapshot) throws {
        guard let accountID = snapshot.accountID,
              let primary = snapshot.primary,
              let secondary = snapshot.secondary,
              primary.minutes == QuotaReducer.expectedPrimaryMinutes,
              secondary.minutes == QuotaReducer.expectedSecondaryMinutes,
              let primaryReset = primary.resetsAt, primaryReset.isFinite,
              let secondaryReset = secondary.resetsAt, secondaryReset.isFinite else { return }

        let digest = Self.digest(accountID: accountID, salt: accountSalt)
        guard let previous = document.baseline, previous.accountDigest == digest else {
            document.baseline = ResetBaseline(
                accountDigest: digest,
                primaryResetAt: primaryReset,
                secondaryResetAt: secondaryReset,
                primaryWasExhausted: primary.isExhausted,
                secondaryWasExhausted: secondary.isExhausted
            )
            document.pendingEvents.removeAll()
            try persist()
            return
        }

        // A response with an older period boundary is stale or inconsistent;
        // it must not move the baseline backwards or create a future false reset.
        guard primaryReset >= previous.primaryResetAt,
              secondaryReset >= previous.secondaryResetAt else { return }

        let previousPendingCount = document.pendingEvents.count
        let sampledAt = snapshot.fetchedAt.timeIntervalSince1970
        appendEventIfConfirmed(window: .primary, duration: QuotaReducer.expectedPrimaryMinutes, wasExhausted: previous.primaryWasExhausted == true, oldBoundary: previous.primaryResetAt, newBoundary: primaryReset, currentWindow: primary, sampledAt: sampledAt, digest: digest)
        appendEventIfConfirmed(window: .secondary, duration: QuotaReducer.expectedSecondaryMinutes, wasExhausted: previous.secondaryWasExhausted == true, oldBoundary: previous.secondaryResetAt, newBoundary: secondaryReset, currentWindow: secondary, sampledAt: sampledAt, digest: digest)
        let primaryBoundaryAdvanced = primaryReset > previous.primaryResetAt
        let secondaryBoundaryAdvanced = secondaryReset > previous.secondaryResetAt
        let updatedBaseline = ResetBaseline(
            accountDigest: digest,
            primaryResetAt: primaryReset,
            secondaryResetAt: secondaryReset,
            primaryWasExhausted: primaryBoundaryAdvanced ? primary.isExhausted : (previous.primaryWasExhausted == true || primary.isExhausted),
            secondaryWasExhausted: secondaryBoundaryAdvanced ? secondary.isExhausted : (previous.secondaryWasExhausted == true || secondary.isExhausted)
        )
        document.baseline = updatedBaseline
        if updatedBaseline != previous || document.pendingEvents.count != previousPendingCount { try persist() }
    }

    /// Claims pending events before presentation to prefer avoiding duplicate popups across crashes.
    public mutating func claimPending() throws -> [ConfirmedResetEvent] {
        let events = document.pendingEvents
        guard !events.isEmpty else { return [] }
        document.deliveredKeys.append(contentsOf: events.map(\.dedupeKey))
        if document.deliveredKeys.count > 512 { document.deliveredKeys.removeFirst(document.deliveredKeys.count - 512) }
        document.pendingEvents.removeAll()
        try persist()
        return events
    }

    private mutating func appendEventIfConfirmed(window: QuotaWindowKind, duration: Int, wasExhausted: Bool, oldBoundary: TimeInterval, newBoundary: TimeInterval, currentWindow: UsageWindow, sampledAt: TimeInterval, digest: String) {
        guard wasExhausted,
              sampledAt >= oldBoundary,
              newBoundary > oldBoundary,
              !currentWindow.isExhausted else { return }
        let key = "\(digest)|\(window.rawValue)|\(duration)|\(oldBoundary.bitPattern)"
        guard !document.deliveredKeys.contains(key), !document.pendingEvents.contains(where: { $0.dedupeKey == key }) else { return }
        document.pendingEvents.append(ConfirmedResetEvent(id: key, window: window, durationMinutes: duration, previousResetAt: oldBoundary, newResetAt: newBoundary, detectedAt: Date(timeIntervalSince1970: sampledAt)))
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(directory.path, mode_t(S_IRWXU)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: fileURL, options: .atomic)
        guard chmod(fileURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func digest(accountID: String, salt: String) -> String {
        let data = Data((salt + "|" + accountID).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
