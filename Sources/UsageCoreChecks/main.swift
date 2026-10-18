import Foundation
import UsageCore

private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private let epoch: TimeInterval = 2_000_000_000
private let uptime: TimeInterval = 500

private func snapshot(
    primaryUsed: Double = 20,
    secondaryUsed: Double = 30,
    primaryReset: TimeInterval? = 2_000_000_300,
    secondaryReset: TimeInterval? = 2_000_010_000,
    permission: Any = true,
    spendControl: Any = false,
    reachedType: Any = NSNull(),
    accountID: Any = "account-a",
    primaryMinutes: Int? = 300,
    secondaryMinutes: Int? = 10_080,
    receivedUptime: TimeInterval? = nil,
    fetchedAt: Date? = nil
) -> UsageSnapshot {
    var primary: [String: Any] = ["usedPercent": primaryUsed]
    var secondary: [String: Any] = ["usedPercent": secondaryUsed]
    if let primaryMinutes { primary["windowDurationMins"] = primaryMinutes }
    if let secondaryMinutes { secondary["windowDurationMins"] = secondaryMinutes }
    if let primaryReset { primary["resetsAt"] = primaryReset }
    if let secondaryReset { secondary["resetsAt"] = secondaryReset }
    let raw: [String: Any] = [
        "rateLimits": ["primary": primary, "secondary": secondary],
        "ordinaryUsageAllowed": permission,
        "spendControlReached": spendControl,
        "rateLimitReachedType": reachedType,
        "accountId": accountID,
    ]
    return UsageSnapshot(raw, fetchedAt: fetchedAt ?? Date(timeIntervalSince1970: epoch), receivedUptime: receivedUptime ?? uptime)!
}

private func reduce(_ value: UsageSnapshot?, preferred: QuotaWindowKind = .primary, now: TimeInterval? = nil, atUptime: TimeInterval? = nil, connected: Bool = true) -> QuotaDecision {
    QuotaReducer.reduce(snapshot: value, now: now ?? epoch, monotonicNow: atUptime ?? uptime, connected: connected, preferredWindow: preferred)
}

let fiveHourBlocked = reduce(snapshot(primaryUsed: 100, secondaryUsed: 15))
expect(fiveHourBlocked.availability == .limited, "5-hour exhaustion remains blocked")
expect(!fiveHourBlocked.canResume, "5-hour exhaustion never resumes")
expect(fiveHourBlocked.displayWindow == .primary, "display the exhausted 5-hour period")
expect(fiveHourBlocked.countdownDeadline == epoch + 300, "5-hour countdown uses its reset time")

let weeklyBlocked = reduce(snapshot(primaryUsed: 15, secondaryUsed: 100), preferred: .primary)
expect(weeklyBlocked.availability == .limited, "weekly exhaustion remains blocked")
expect(!weeklyBlocked.canResume, "weekly exhaustion never resumes")
expect(weeklyBlocked.displayWindow == .secondary, "weekly exhaustion overrides 5-hour preference")
expect(weeklyBlocked.countdownDeadline == epoch + 10_000, "weekly countdown uses its reset time")

let bothBlocked = reduce(snapshot(primaryUsed: 100, secondaryUsed: 100, primaryReset: epoch + 300, secondaryReset: epoch + 10_000))
expect(bothBlocked.availability == .limited, "both exhausted remain blocked")
expect(bothBlocked.countdownDeadline == epoch + 10_000, "both exhausted use the later reset")
expect(bothBlocked.displayWindow == .secondary, "show the later blocking reset")

let available = reduce(snapshot(primaryUsed: 0, secondaryUsed: 99.2))
expect(available.availability == .available && available.canResume, "both known windows plus permission allow resume")
expect(available.displayWindow == .primary, "available display respects preference")
expect(UsageWindow(json: ["usedPercent": 99.2])?.remainingText == "<1%", "fractional remainder does not display 0%")

expect(ResetSoundPolicy.shouldPlay(enabled: true, wasAvailable: false, accountChanged: false, hasConfirmedReset: true, isAvailable: true), "enabled chime plays for a confirmed transition to full availability")
expect(!ResetSoundPolicy.shouldPlay(enabled: false, wasAvailable: false, accountChanged: false, hasConfirmedReset: true, isAvailable: true), "disabled chime stays silent")
expect(!ResetSoundPolicy.shouldPlay(enabled: true, wasAvailable: true, accountChanged: false, hasConfirmedReset: true, isAvailable: true), "an already available state does not replay the chime")
expect(!ResetSoundPolicy.shouldPlay(enabled: true, wasAvailable: false, accountChanged: true, hasConfirmedReset: true, isAvailable: true), "account changes never play a reset chime")
expect(!ResetSoundPolicy.shouldPlay(enabled: true, wasAvailable: false, accountChanged: false, hasConfirmedReset: false, isAvailable: true), "availability without a confirmed reset event stays silent")
expect(!ResetSoundPolicy.shouldPlay(enabled: true, wasAvailable: false, accountChanged: false, hasConfirmedReset: true, isAvailable: false), "a partial or unknown reset stays silent")

expect(reduce(snapshot(permission: NSNull())).availability == .unknown, "missing permission never implies availability")
let unknownPermissionBlocked = reduce(snapshot(primaryUsed: 100, secondaryUsed: 10, permission: NSNull()))
expect(unknownPermissionBlocked.countdownDeadline == epoch + 300, "known exhausted window still has a window-specific countdown")
expect(!unknownPermissionBlocked.canResume, "window countdown with unknown permission does not enable resume")
expect(reduce(snapshot(permission: false)).availability == .restricted, "permission denied blocks resume")
let otherLimitAndExhausted = reduce(snapshot(secondaryUsed: 100, spendControl: true), preferred: .primary)
expect(otherLimitAndExhausted.countdownDeadline == epoch + 10_000, "show the quota window countdown despite a separate block")
expect(!otherLimitAndExhausted.canResume, "separate server block still prevents resume")
expect(reduce(snapshot(reachedType: "workspace_member_usage_limit_reached")).availability == .restricted, "server limit reason blocks resume")
expect(reduce(snapshot(spendControl: true)).availability == .restricted, "spend control blocks resume")
expect(reduce(snapshot(accountID: NSNull())).availability == .unknown, "missing account scope blocks resume")
expect(reduce(snapshot(primaryMinutes: nil)).availability == .unknown, "missing primary period blocks resume")
expect(reduce(snapshot(secondaryMinutes: 1_440)).availability == .unknown, "unexpected secondary period blocks resume")
let knownPrimaryOnly = reduce(snapshot(primaryUsed: 100, secondaryMinutes: nil))
expect(knownPrimaryOnly.countdownDeadline == epoch + 300, "known primary can count down while weekly window is unknown")
expect(!knownPrimaryOnly.canResume, "unknown weekly window still prevents resume")
expect(UsageWindow(json: ["usedPercent": true]) == nil, "boolean is not a valid used percentage")
expect(UsageWindow(json: ["usedPercent": 10.0, "windowDurationMins": 300.5])?.minutes == nil, "fractional duration is not truncated")
expect(reduce(snapshot(), atUptime: uptime + 91).availability == .unknown, "stale snapshot blocks resume")
expect(reduce(snapshot(), atUptime: uptime - 1).availability == .unknown, "invalid monotonic age blocks resume")
expect(reduce(snapshot(), connected: false).availability == .unknown, "disconnected snapshot blocks resume")

let due = reduce(snapshot(primaryUsed: 100, secondaryUsed: 10, primaryReset: epoch - 1), now: epoch)
expect(due.availability == .confirming && !due.canResume, "elapsed countdown requests server confirmation")
let over = UsageWindow(json: ["usedPercent": 112.0])
expect(over?.remainingPercent == 0, "over-limit display clamps to zero")
expect(reduce(snapshot(primaryUsed: 112, secondaryUsed: 1)).availability == .limited, "over-limit raw use remains exhausted")

let codexResponse: [String: Any] = [
    "accountId": "account-a",
    "ordinaryUsageAllowed": true,
    "rateLimitsByLimitId": [
        "codex": ["primary": ["usedPercent": 20.0, "windowDurationMins": 300], "secondary": ["usedPercent": 30.0, "windowDurationMins": 10_080]],
        "other": ["primary": ["usedPercent": 99.0, "windowDurationMins": 300]],
    ],
    "rateLimits": ["primary": ["usedPercent": 100.0, "windowDurationMins": 300]],
]
expect(UsageSnapshot(codexResponse)?.primary?.usedPercent == 20, "select Codex bucket over all fallbacks")
let noCodex: [String: Any] = ["rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 10]]], "rateLimits": ["primary": ["usedPercent": 10]]]
expect(UsageSnapshot(noCodex) == nil, "never replace a missing Codex bucket with another bucket")

let ideaDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-usage-check-\(UUID().uuidString)", isDirectory: true)
let ideaURL = ideaDirectory.appendingPathComponent("ideas.json")
try! FileManager.default.createDirectory(at: ideaDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: ideaDirectory) }
var ideaStore = IdeaStore(fileURL: ideaURL)
try! ideaStore.load()
try! ideaStore.setDraft("把状态机接到菜单栏")
var restoredStore = IdeaStore(fileURL: ideaURL)
try! restoredStore.load()
expect(restoredStore.draft == "把状态机接到菜单栏", "draft survives a store reload")
let savedIdea = try! restoredStore.saveIdea()
expect(restoredStore.draft.isEmpty && restoredStore.ideas.first?.id == savedIdea.id, "save commits idea and then clears draft")
var afterSave = IdeaStore(fileURL: ideaURL)
try! afterSave.load()
expect(afterSave.ideas.first?.text == "把状态机接到菜单栏", "saved idea survives a store reload")
try! afterSave.updateIdea(id: savedIdea.id, text: "把双额度状态机接到菜单栏")
expect(afterSave.ideas.first?.text == "把双额度状态机接到菜单栏", "saved ideas can be edited")
try! afterSave.deleteIdea(id: savedIdea.id)
expect(afterSave.ideas.isEmpty, "saved ideas can be deleted")
let directoryMode = (try! FileManager.default.attributesOfItem(atPath: ideaDirectory.path)[.posixPermissions] as! NSNumber).intValue & 0o777
let fileMode = (try! FileManager.default.attributesOfItem(atPath: ideaURL.path)[.posixPermissions] as! NSNumber).intValue & 0o777
expect(directoryMode == 0o700 && fileMode == 0o600, "idea data uses private local file permissions")

let corruptURL = ideaDirectory.appendingPathComponent("corrupt.json")
let corruptBytes = Data("not json".utf8)
try! corruptBytes.write(to: corruptURL)
var corruptStore = IdeaStore(fileURL: corruptURL)
var corruptWasRejected = false
do { try corruptStore.load() } catch { corruptWasRejected = true }
expect(corruptWasRejected && (try! Data(contentsOf: corruptURL)) == corruptBytes, "corrupt idea file is rejected without overwriting it")

let blockedURL = ideaDirectory.appendingPathComponent("blocked.json")
try! FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: false)
var failedWriteStore = IdeaStore(fileURL: blockedURL)
var writeFailed = false
do { try failedWriteStore.setDraft("仍保留在编辑器里的草稿") } catch { writeFailed = true }
expect(writeFailed && failedWriteStore.draft == "仍保留在编辑器里的草稿", "failed write keeps draft in memory")

let trackerURL = ideaDirectory.appendingPathComponent("quota-resets.json")
var tracker = ResetTracker(fileURL: trackerURL, accountSalt: "test-install-salt")
try! tracker.load()
try! tracker.observe(snapshot(primaryUsed: 100, secondaryUsed: 25, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch)))
expect(try! tracker.claimPending().isEmpty, "first valid snapshot establishes a baseline without celebration")
try! tracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
expect(try! tracker.claimPending().isEmpty, "usage drop alone is not a reset event")
try! tracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 302)))
let oneReset = try! tracker.claimPending()
expect(oneReset.count == 1 && oneReset.first?.window == .primary, "confirmed 5-hour boundary advance emits one period event")
expect(oneReset.first?.previousResetAt == epoch + 300 && oneReset.first?.newResetAt == epoch + 600, "reset event carries the observed old and new boundaries")
try! tracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 303)))
expect(try! tracker.claimPending().isEmpty, "repeated response cannot repeat a claimed reset")
var trackerAfterClaim = ResetTracker(fileURL: trackerURL, accountSalt: "test-install-salt")
try! trackerAfterClaim.load()
try! trackerAfterClaim.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 304)))
expect(try! trackerAfterClaim.claimPending().isEmpty, "claimed reset stays deduplicated after a restart")
let trackerData = try! String(contentsOf: trackerURL, encoding: .utf8)
expect(!trackerData.contains("account-a"), "reset persistence stores only a salted account digest")

let earlyTracker = ideaDirectory.appendingPathComponent("early-boundary.json")
var earlyBoundary = ResetTracker(fileURL: earlyTracker, accountSalt: "test-install-salt")
try! earlyBoundary.observe(snapshot(primaryUsed: 100, secondaryUsed: 20, primaryReset: epoch + 300, secondaryReset: epoch + 10_000))
try! earlyBoundary.observe(snapshot(primaryUsed: 20, secondaryUsed: 20, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 200)))
expect(try! earlyBoundary.claimPending().isEmpty, "boundary advance before the prior reset time is not confirmed")
try! earlyBoundary.observe(snapshot(primaryUsed: 100, secondaryUsed: 20, primaryReset: epoch + 900, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 601)))
expect(try! earlyBoundary.claimPending().isEmpty, "a reset is not celebrated while the returned window remains exhausted")

let persistedTrackerURL = ideaDirectory.appendingPathComponent("restart-tracker.json")
var trackerBeforeRestart = ResetTracker(fileURL: persistedTrackerURL, accountSalt: "test-install-salt")
try! trackerBeforeRestart.observe(snapshot(primaryUsed: 100, secondaryUsed: 25, primaryReset: epoch + 300, secondaryReset: epoch + 10_000))
var trackerAfterRestart = ResetTracker(fileURL: persistedTrackerURL, accountSalt: "test-install-salt")
try! trackerAfterRestart.load()
try! trackerAfterRestart.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
expect(try! trackerAfterRestart.claimPending().count == 1, "reset boundary survives an application restart")

let combinedTrackerURL = ideaDirectory.appendingPathComponent("combined-tracker.json")
var combinedTracker = ResetTracker(fileURL: combinedTrackerURL, accountSalt: "test-install-salt")
try! combinedTracker.observe(snapshot(primaryUsed: 100, secondaryUsed: 100, primaryReset: epoch + 300, secondaryReset: epoch + 500))
try! combinedTracker.observe(snapshot(primaryUsed: 12, secondaryUsed: 13, primaryReset: epoch + 600, secondaryReset: epoch + 900, fetchedAt: Date(timeIntervalSince1970: epoch + 501)))
let combinedEvents = try! combinedTracker.claimPending()
expect(combinedEvents.count == 2, "two confirmed window resets remain separate events for coalesced display")

let idleTrackerURL = ideaDirectory.appendingPathComponent("idle-window.json")
var idleTracker = ResetTracker(fileURL: idleTrackerURL, accountSalt: "test-install-salt")
try! idleTracker.observe(snapshot(primaryUsed: 20, secondaryUsed: 25, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch)))
try! idleTracker.observe(snapshot(primaryUsed: 15, secondaryUsed: 25, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
expect(try! idleTracker.claimPending().isEmpty, "a routine period boundary does not celebrate an unexhausted window")

let partialTrackerURL = ideaDirectory.appendingPathComponent("partial-recovery.json")
var partialTracker = ResetTracker(fileURL: partialTrackerURL, accountSalt: "test-install-salt")
try! partialTracker.observe(snapshot(primaryUsed: 100, secondaryUsed: 100, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch)))
try! partialTracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 100, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
let partialEvents = try! partialTracker.claimPending()
let partialDecision = reduce(snapshot(primaryUsed: 10, secondaryUsed: 100))
expect(partialEvents.count == 1 && partialEvents.first?.window == .primary, "one window can reset while the other remains exhausted")
expect(partialDecision.availability == .limited && !partialDecision.canResume, "a single reset never advertises restored Codex availability")

let rehearsalTrackerURL = ideaDirectory.appendingPathComponent("demo-rehearsal.json")
var rehearsalTracker = ResetTracker(fileURL: rehearsalTrackerURL, accountSalt: "demo-only-salt")
try! rehearsalTracker.observe(snapshot(primaryUsed: 100, secondaryUsed: 100, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch)))
expect(try! rehearsalTracker.claimPending().isEmpty, "demo rehearsal starts from an exhausted baseline without inventing an event")
try! rehearsalTracker.observe(snapshot(primaryUsed: 0, secondaryUsed: 100, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
let rehearsalPartial = try! rehearsalTracker.claimPending()
expect(rehearsalPartial.count == 1 && rehearsalPartial[0].window == .primary, "demo rehearsal confirms only the 5-hour reset first")
let rehearsalPartialDecision = reduce(snapshot(primaryUsed: 0, secondaryUsed: 100), now: epoch + 301)
expect(!rehearsalPartialDecision.canResume && rehearsalPartialDecision.availability == .limited, "demo partial recovery keeps the 7-day exhausted gate")
try! rehearsalTracker.observe(snapshot(primaryUsed: 0, secondaryUsed: 100, primaryReset: epoch + 600, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 302)))
expect(try! rehearsalTracker.claimPending().isEmpty, "demo duplicate response does not create a second reset popup")
let rehearsalFullSnapshot = snapshot(primaryUsed: 0, secondaryUsed: 22, primaryReset: epoch + 600, secondaryReset: epoch + 20_000, fetchedAt: Date(timeIntervalSince1970: epoch + 10_001))
try! rehearsalTracker.observe(rehearsalFullSnapshot)
let rehearsalFull = try! rehearsalTracker.claimPending()
let rehearsalAvailable = reduce(rehearsalFullSnapshot, now: epoch + 10_001)
expect(rehearsalFull.count == 1 && rehearsalFull[0].window == .secondary, "demo rehearsal confirms the later 7-day reset")
expect(rehearsalAvailable.canResume && rehearsalAvailable.availability == .available, "demo full recovery enables the idea reminder only after both windows recover")
let reexhaustedSnapshot = snapshot(primaryUsed: 100, secondaryUsed: 22, primaryReset: epoch + 10_600, secondaryReset: epoch + 20_000, fetchedAt: Date(timeIntervalSince1970: epoch + 10_002))
try! rehearsalTracker.observe(reexhaustedSnapshot)
let reexhaustedDecision = reduce(reexhaustedSnapshot, now: epoch + 10_002)
expect(try! rehearsalTracker.claimPending().isEmpty, "re-exhaustion while the panel is open does not replay an old reset event")
expect(reexhaustedDecision.availability == .limited && !reexhaustedDecision.canResume, "re-exhaustion immediately restores the quota block")
try! rehearsalTracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 22, primaryReset: epoch + 11_200, secondaryReset: epoch + 20_000, fetchedAt: Date(timeIntervalSince1970: epoch + 10_601)))
let nextCycleReset = try! rehearsalTracker.claimPending()
expect(nextCycleReset.count == 1 && nextCycleReset[0].window == .primary, "the next genuine cycle can still report its own confirmed reset")

let rollbackTrackerURL = ideaDirectory.appendingPathComponent("rollback-boundary.json")
var rollbackTracker = ResetTracker(fileURL: rollbackTrackerURL, accountSalt: "test-install-salt")
try! rollbackTracker.observe(snapshot(primaryUsed: 100, secondaryUsed: 25, primaryReset: epoch + 300, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch)))
try! rollbackTracker.observe(snapshot(primaryUsed: 10, secondaryUsed: 25, primaryReset: epoch + 200, secondaryReset: epoch + 10_000, fetchedAt: Date(timeIntervalSince1970: epoch + 301)))
expect(try! rollbackTracker.claimPending().isEmpty, "an older reset boundary cannot create a false event")

let switchedAccount = snapshot(primaryUsed: 10, secondaryUsed: 10, primaryReset: epoch + 900, secondaryReset: epoch + 11_000, accountID: "account-b", fetchedAt: Date(timeIntervalSince1970: epoch + 1_000))
try! tracker.observe(switchedAccount)
expect(try! tracker.claimPending().isEmpty, "account change establishes a fresh baseline without replay")

let quoteIDs = (1...99).map { "quote-\($0)" }
var quoteBag = QuoteShuffleBag()
var quoteRandom = SystemRandomNumberGenerator()
let firstQuoteRun = (0..<99).compactMap { _ in quoteBag.nextID(from: quoteIDs, using: &quoteRandom) }
expect(firstQuoteRun.count == 99 && Set(firstQuoteRun).count == 99, "quote shuffle bag visits every quote once before repeating")
let bagBytes = try! JSONEncoder().encode(quoteBag)
var restoredQuoteBag = try! JSONDecoder().decode(QuoteShuffleBag.self, from: bagBytes)
let nextQuote = restoredQuoteBag.nextID(from: quoteIDs, using: &quoteRandom)
expect(nextQuote != firstQuoteRun.last, "quote shuffle bag avoids a repeat when a new bag begins")
let deduplicatedQuoteIDs = ["same", "same", "", "unique"]
var smallQuoteBag = QuoteShuffleBag()
let smallRun = (0..<2).compactMap { _ in smallQuoteBag.nextID(from: deduplicatedQuoteIDs, using: &quoteRandom) }
expect(smallRun.count == 2 && Set(smallRun).count == 2, "quote bag ignores empty and duplicate identifiers")

print("\(checks) core quota checks passed")
