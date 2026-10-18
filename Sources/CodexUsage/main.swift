import AppKit
import CFNetwork
import Darwin
import UsageCore
import UniformTypeIdentifiers

// App-server owns authentication. This client never reads or logs credentials.
final class UsageClient {
    var onUpdate: ((Result<UsageSnapshot, Error>) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var pending = false
    private var requestID = 1
    private var deadline: DispatchWorkItem?
    private let reader = DispatchQueue(label: "codex-usage-reader")

    func refresh() {
        guard !pending else { return }
        pending = true
        let timeout = DispatchWorkItem { [weak self] in self?.fail("读取超时，请检查网络或 Codex 登录状态") }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        if process?.isRunning == true { requestUsage(); return }
        do {
            let p = Process()
            let candidates = [Bundle.main.resourcePath.map { $0 + "/codex-path" }]
                .compactMap { $0 }.compactMap { try? String(contentsOfFile: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
                + [NSHomeDirectory() + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw NSError(domain: "UsageBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 Codex CLI，请安装后重试"])
            }
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = ["app-server", "--listen", "stdio://"]
            p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
            var env = ProcessInfo.processInfo.environment
            // Respect explicit proxy env first, otherwise inherit macOS HTTPS proxy.
            if env["HTTPS_PROXY"] == nil && env["https_proxy"] == nil,
               let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
               settings[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1,
               let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
               let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int {
                var proxy = URLComponents(); proxy.scheme = "http"; proxy.host = host; proxy.port = port
                env["HTTPS_PROXY"] = proxy.string
            }
            p.environment = env
            let stdin = Pipe(), stdout = Pipe()
            p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
            try p.run()
            process = p; input = stdin.fileHandleForWriting
            reader.async { [weak self] in
                var buffer = Data()
                while true {
                    let bytes = stdout.fileHandleForReading.availableData
                    if bytes.isEmpty { break }
                    buffer.append(bytes)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                        DispatchQueue.main.async {
                            guard self?.process === p else { return }
                            self?.receive(message)
                        }
                    }
                }
                DispatchQueue.main.async {
                    guard self?.process === p else { return }
                    self?.fail("Codex 连接已断开，稍后自动重试")
                }
            }
            send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_bar", "version": "1.0.0"]]])
        } catch { fail(error.localizedDescription) }
    }
    private func send(_ message: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
            try input?.write(contentsOf: data)
        } catch { fail("无法写入 Codex 连接") }
    }
    private func requestUsage() {
        requestID += 1
        send(["id": requestID, "method": "account/rateLimits/read"])
    }
    private func receive(_ message: [String: Any]) {
        if message["id"] as? Int == 0 {
            guard message["error"] == nil else { fail("Codex 初始化失败，请更新 CLI 后重试"); return }
            send(["method": "initialized", "params": [:]])
            requestUsage(); return
        }
        guard message["id"] as? Int == requestID else { return }
        guard let result = message["result"] as? [String: Any], let snapshot = UsageSnapshot(result) else {
            fail("无法获取额度，请检查 Codex 登录状态及网络"); return
        }
        pending = false; deadline?.cancel(); onUpdate?(.success(snapshot))
    }
    private func fail(_ text: String) {
        pending = false; deadline?.cancel(); stop()
        onUpdate?(.failure(NSError(domain: "UsageBar", code: 2, userInfo: [NSLocalizedDescriptionKey: text])))
    }
    func stop() {
        input?.closeFile(); input = nil
        let p = process; process = nil
        if let p, p.isRunning {
            p.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if p.isRunning { _ = kill(p.processIdentifier, SIGKILL) }
            }
        }
    }
}

func quotaStatusImage(label: String, fillPercent: Double?, dark: Bool = false) -> NSImage {
    let foreground = dark ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)
    let trackColor = foreground.withAlphaComponent(0.16)
    let textStyle: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: foreground]
    let textSize = label.size(withAttributes: textStyle)
    let contentWidth = max(28, textSize.width + 6)
    let imageWidth = contentWidth + 16
    let image = NSImage(size: NSSize(width: imageWidth, height: 20), flipped: false) { _ in
        let interior = NSRect(x: 8, y: 4, width: contentWidth, height: 12)
        // Open code brackets keep the silhouette distinct from the system battery.
        foreground.setStroke()
        let brackets = NSBezierPath()
        brackets.move(to: NSPoint(x: 5, y: 16))
        brackets.line(to: NSPoint(x: 1, y: 10))
        brackets.line(to: NSPoint(x: 5, y: 4))
        brackets.move(to: NSPoint(x: interior.maxX + 3, y: 16))
        brackets.line(to: NSPoint(x: interior.maxX + 7, y: 10))
        brackets.line(to: NSPoint(x: interior.maxX + 3, y: 4))
        brackets.lineWidth = 1.4
        brackets.lineCapStyle = .round
        brackets.lineJoinStyle = .round
        brackets.stroke()

        let fraction = fillPercent.flatMap { $0.isFinite ? max(0, min(100, $0)) / 100 : nil } ?? 0
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: interior, xRadius: 6, yRadius: 6).addClip()
        trackColor.setFill()
        NSBezierPath(roundedRect: interior, xRadius: 6, yRadius: 6).fill()
        let filledRect = NSRect(x: interior.minX, y: interior.minY, width: interior.width * fraction, height: interior.height)
        if fraction > 0 {
            foreground.setFill()
            NSBezierPath(rect: filledRect).fill()
        }
        let point = NSPoint(x: interior.midX - textSize.width / 2, y: interior.midY - textSize.height / 2)
        // Invert only the digits overlapping the filled portion; the complete trough keeps the scale legible.
        label.draw(at: point, withAttributes: textStyle)
        if fraction > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: filledRect).addClip()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            label.draw(at: point, withAttributes: textStyle)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    image.isTemplate = false
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private var instanceLockDescriptor: Int32 = -1
    private let client = UsageClient()
    private var refreshTimer: Timer?
    private var countdownTimer: Timer?
    private var draftSaveTimer: Timer?
    private var popover: NSPopover!
    private var popoverController: QuotaPopoverViewController!
    private var ideaLibraryWindow: IdeaLibraryWindowController!
    private var celebrationPanel: ResetCelebrationPanel!
    private var ideaStore = IdeaStore(fileURL: IdeaStore.defaultFileURL())
    private var resetTracker: ResetTracker?
    private var draftForFlush = ""
    private var draftPersistenceNeedsRetry = false
    private var ideaStoreLoadFailure = false
    private var resetTrackerLoadFailure = false
    private var snapshot: UsageSnapshot?
    private var quotaReadFailed = false
    private var language = AppLanguage.initial()
    private var quoteBag = QuoteShuffleBag()
    private var currentQuote: FamousQuote?
    private let demoMode = CommandLine.arguments.contains("--demo")
    private var demoTimer: Timer?
    private var demoNow: TimeInterval?
    private var demoRoot: URL?
    private var demoStepIndex = 0
    private var weekly = !CommandLine.arguments.contains("--demo") && UserDefaults.standard.bool(forKey: "showWeekly")
    private var confirmationRefreshAttempted = false
    private var resetSoundEnabled = UserDefaults.standard.bool(forKey: "codexUsage.resetSoundEnabled")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else { NSApp.terminate(nil); return }
        status = NSStatusBar.system.statusItem(withLength: 44)
        status.button?.target = self
        status.button?.action = #selector(togglePopover(_:))
        if demoMode {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-usage-demo-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                FileManager.default.createFile(atPath: root.appendingPathComponent("events.jsonl").path, contents: Data(), attributes: [.posixPermissions: 0o600])
                demoRoot = root
                ideaStore = IdeaStore(fileURL: root.appendingPathComponent("ideas.json"))
                fputs("Codex Usage demo data directory: \(root.path)\n", stderr)
            } catch {
                fputs("Could not create isolated demo directory: \(error.localizedDescription)\n", stderr)
                NSApp.terminate(nil)
                return
            }
        }
        do { try ideaStore.load(); draftForFlush = ideaStore.draft }
        catch { ideaStoreLoadFailure = true }
        if demoMode, ideaStore.ideas.isEmpty {
            _ = try? ideaStore.saveIdea("演示想法：验证双额度恢复后，再继续完善菜单栏体验。")
        }
        setupPopover()
        if demoMode { popoverController.setDemoMode(true) }
        setupResetTracker()
        if ideaStoreLoadFailure { popoverController.setNotice(AppNotice.ideasUnreadable.text(in: language)) }
        else if resetTrackerLoadFailure { popoverController.setNotice(AppNotice.resetTrackerUnavailable.text(in: language)) }
        client.onUpdate = { [weak self] result in
            switch result {
            case .success(let value): self?.acceptSnapshot(value)
            case .failure:
                guard let self else { return }
                self.quotaReadFailed = true
                if self.celebrationPanel.isVisible {
                    self.celebrationPanel.refresh(snapshot: nil, decision: self.currentDecision(), idea: nil, language: self.language)
                }
                self.render()
            }
        }
        render()
        if demoMode {
            startDemoSequence()
        } else {
            client.refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.client.refresh() }
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        if !demoMode {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        }
    }
    private func currentDecision() -> QuotaDecision {
            QuotaReducer.reduce(snapshot: snapshot, now: demoNow ?? Date().timeIntervalSince1970, monotonicNow: ProcessInfo.processInfo.systemUptime, connected: !quotaReadFailed, preferredWindow: weekly ? .secondary : .primary)
    }
    @discardableResult
    private func acceptSnapshot(_ value: UsageSnapshot) -> Bool {
        let wasAvailable = currentDecision().canResume
        let accountChanged = snapshot.map { $0.accountID != value.accountID } ?? false
        if accountChanged { celebrationPanel.close() }
        snapshot = value
        quotaReadFailed = false
        confirmationRefreshAttempted = false
        let presentedReset = observeResets(value, wasAvailable: wasAvailable, accountChanged: accountChanged)
        if !presentedReset, celebrationPanel.isVisible {
            celebrationPanel.refresh(snapshot: value, decision: currentDecision(), idea: resetIdeaPreview(), language: language)
        }
        render()
        return presentedReset
    }
    private func tick() {
        let decision = currentDecision()
        if !demoMode, decision.availability == .confirming, !confirmationRefreshAttempted {
            confirmationRefreshAttempted = true
            client.refresh()
        }
        render()
    }
    private func countdownText(until deadline: TimeInterval) -> String {
        language.duration(max(0, Int(ceil(deadline - Date().timeIntervalSince1970))))
    }
    private func render(forceDraft: Bool = false) {
        let decision = currentDecision()
        let selected = decision.displayWindow ?? (weekly ? .secondary : .primary)
        let selectedValue = snapshot?.window(selected)
        let countdown = decision.countdownDeadline
        let label: String
        let fill: Double?
        if let countdown {
            label = countdownText(until: countdown); fill = 0
        } else if decision.availability == .available, let selectedValue {
            label = selectedValue.remainingText; fill = selectedValue.remainingPercent
        } else if decision.availability == .restricted {
            label = "!"; fill = nil
        } else {
            label = "—"; fill = nil
        }
        let imageLabel = demoMode ? "D\(label)" : label
        let isDark = status.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let image = quotaStatusImage(label: imageLabel, fillPercent: fill, dark: isDark)
        status.length = image.size.width + 6
        status.button?.image = image
        let shortState = stateLabel(decision.availability)
        let primaryText = snapshot?.primary?.remainingText ?? language.text("未知", "unknown")
        let secondaryText = snapshot?.secondary?.remainingText ?? language.text("未知", "unknown")
        let demoPrefix = demoMode ? language.text("演示数据 · ", "DEMO DATA · ") : ""
        let statusValue = countdown == nil
            ? language.text("当前显示 \(label)", "Showing \(label)")
            : language.text("重置倒计时 \(label)", "Reset countdown \(label)")
        status.button?.setAccessibilityLabel(language.text("\(demoPrefix)Codex 使用额度 · 5 小时 \(primaryText) · 7 天 \(secondaryText) · \(shortState) · \(statusValue)", "\(demoPrefix)Codex usage · 5-hour \(primaryText) · 7-day \(secondaryText) · \(shortState) · \(statusValue)"))
        let failureText = quotaReadFailed ? AppNotice.quotaReadFailed.text(in: language) : nil
        status.button?.toolTip = language.text("\(demoPrefix)Codex · \(shortState)\n5 小时：\(primaryText) · 7 天：\(secondaryText)\n\(failureText ?? language.reason(decision.reason))", "\(demoPrefix)Codex · \(shortState)\n5-hour: \(primaryText) · 7-day: \(secondaryText)\n\(failureText ?? language.reason(decision.reason))")
        popoverController.update(snapshot: snapshot, decision: decision, error: failureText, draft: ideaStore.draft, ideas: ideaStore.ideas, weekly: weekly, storageAvailable: !ideaStoreLoadFailure, language: language, quote: currentQuote, forceDraft: forceDraft)
        ideaLibraryWindow?.update(ideas: ideaStore.ideas, language: language)
    }
    private func setupPopover() {
        if !demoMode, let data = UserDefaults.standard.data(forKey: "codexUsage.quoteShuffleBag"),
           let savedBag = try? JSONDecoder().decode(QuoteShuffleBag.self, from: data) {
            quoteBag = savedBag
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 540)
        popoverController = QuotaPopoverViewController()
        ideaLibraryWindow = IdeaLibraryWindowController()
        popover.contentViewController = popoverController
        popoverController.onDraftChanged = { [weak self] in self?.scheduleDraftSave($0) }
        popoverController.onSaveIdea = { [weak self] id, text in self?.saveIdea(id: id, text: text) ?? AppNotice.ideaWriteFailed.text(in: self?.language ?? .chinese) }
        popoverController.onOpenIdeaLibrary = { [weak self] in
            guard let self else { return }
            self.ideaLibraryWindow.show(ideas: self.ideaStore.ideas, language: self.language)
        }
        ideaLibraryWindow.onEditIdea = { [weak self] id in self?.showPopover(focusIdeaID: id) }
        ideaLibraryWindow.onNewIdea = { [weak self] in self?.showPopover(forceDraft: true) }
        ideaLibraryWindow.onDeleteIdea = { [weak self] id in self?.deleteIdea(id: id) ?? false }
        ideaLibraryWindow.onCopyIdea = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        popoverController.onRefresh = { [weak self] in
            guard let self, !self.demoMode else { return }
            self.client.refresh()
        }
        popoverController.onQuit = { [weak self] in self?.quit() }
        popoverController.onClose = { [weak self] in self?.popover.performClose(nil) }
        popoverController.onSelectWindow = { [weak self] weekly in
            guard let self else { return }
            self.weekly = weekly
            if !self.demoMode { UserDefaults.standard.set(weekly, forKey: "showWeekly") }
            self.render()
        }
        popoverController.onSelectLanguage = { [weak self] selectedLanguage in
            guard let self else { return }
            self.language = selectedLanguage
            if !self.demoMode { UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "codexUsage.language") }
            self.celebrationPanel.setLanguage(selectedLanguage)
            if self.celebrationPanel.isVisible {
                self.celebrationPanel.refresh(snapshot: self.snapshot, decision: self.currentDecision(), idea: self.resetIdeaPreview(), language: selectedLanguage)
            }
            self.render()
            if self.ideaStoreLoadFailure { self.popoverController.setNotice(AppNotice.ideasUnreadable.text(in: selectedLanguage)) }
            else if self.resetTrackerLoadFailure { self.popoverController.setNotice(AppNotice.resetTrackerUnavailable.text(in: selectedLanguage)) }
        }
        popoverController.onOpenQuoteSource = { url in NSWorkspace.shared.open(url) }
        popoverController.onExportIdeas = { [weak self] in self?.exportIdeas() }
        popoverController.setResetSoundEnabled(resetSoundEnabled)
        popoverController.onResetSoundChanged = { [weak self] enabled in
            guard let self else { return }
            self.resetSoundEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "codexUsage.resetSoundEnabled")
        }
        popoverController.onPreviewResetSound = { ResetSoundPlayer.shared.play() }
    }

    private func selectQuoteForPopoverOpening() {
        var generator = SystemRandomNumberGenerator()
        let id = quoteBag.nextID(from: QuoteCatalog.quotes.map(\.id), using: &generator)
        currentQuote = QuoteCatalog.quote(id: id)
        if !demoMode, let data = try? JSONEncoder().encode(quoteBag) {
            UserDefaults.standard.set(data, forKey: "codexUsage.quoteShuffleBag")
        }
    }
    private func acquireSingleInstanceLock() -> Bool {
        let lockSuffix = demoMode ? "-demo" : ""
        let lockPath = "/tmp/local.codex.usage-bar\(lockSuffix).\(getuid()).lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); return false }
        _ = fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR))
        instanceLockDescriptor = descriptor
        return true
    }
    private func resetIdeaPreview() -> ResetIdeaPreview? {
        let draft = draftForFlush.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            return ResetIdeaPreview(text: draft, savedIdeaID: nil, isDraft: true)
        }
        guard let idea = ideaStore.ideas.first else { return nil }
        return ResetIdeaPreview(text: idea.text, savedIdeaID: idea.id, isDraft: false)
    }

    private func setupResetTracker() {
        let salt: String
        let trackerURL: URL
        if demoMode, let demoRoot {
            salt = "demo-only-salt"
            trackerURL = demoRoot.appendingPathComponent("quota-resets.json")
        } else {
            let defaults = UserDefaults.standard
            let saltKey = "quotaResetDigestSalt"
            if let existing = defaults.string(forKey: saltKey) { salt = existing }
            else { salt = UUID().uuidString; defaults.set(salt, forKey: saltKey) }
            trackerURL = ResetTracker.defaultFileURL()
        }
        var tracker = ResetTracker(fileURL: trackerURL, accountSalt: salt)
        do { try tracker.load(); resetTracker = tracker }
        catch { resetTracker = nil; resetTrackerLoadFailure = true }
        celebrationPanel = ResetCelebrationPanel()
        if demoMode { celebrationPanel.setDemoMode(true) }
        celebrationPanel.setLanguage(language)
        celebrationPanel.onOpenIdeas = { [weak self] ideaID, focusDraft in
            guard let self else { return }
            self.celebrationPanel.close()
            self.ideaLibraryWindow.close()
            self.showPopover(forceDraft: focusDraft, focusIdeaID: ideaID)
        }
    }

    private func startDemoSequence() {
        let base = Date().timeIntervalSince1970
        let scenarios: [(String, Double, Double, Double, Double, Double, Bool?)] = [
            ("5 小时与 7 天均耗尽", 100, 100, 300, 10_080, 0, true),
            ("5 小时恢复，7 天仍耗尽", 0, 100, 600, 10_080, 301, true),
            ("重复回包，不重复弹窗", 0, 100, 600, 10_080, 302, true),
            ("两个额度均已恢复", 0, 22, 600, 20_160, 10_081, true),
            ("面板打开后再次耗尽，退出庆祝状态", 100, 22, 10_600, 20_160, 10_082, true),
            ("许可未知，保持待确认", 0, 22, 10_600, 20_160, 10_083, nil),
            ("服务端拒绝，保持受限", 0, 22, 10_600, 20_160, 10_084, false),
            ("重置时间已到，等待新确认", 100, 100, 10_800, 20_160, 20_161, true),
        ]
        func recordDemoScenario(_ name: String, availability: String, canResume: Bool, resetPopup: Bool, snapshotValid: Bool) {
            guard let root = demoRoot,
                  let handle = try? FileHandle(forWritingTo: root.appendingPathComponent("events.jsonl")) else { return }
            _ = try? handle.seekToEnd()
            let record = "{\"scenario\":\"\(name)\",\"availability\":\"\(availability)\",\"canResume\":\(canResume),\"resetPopup\":\(resetPopup),\"snapshotValid\":\(snapshotValid),\"demo\":true}\n"
            try? handle.write(contentsOf: Data(record.utf8))
            try? handle.close()
        }
        func applyNext() {
            guard scenarios.indices.contains(demoStepIndex) else {
                demoTimer?.invalidate(); demoTimer = nil
                return
            }
            let (name, primaryUsed, secondaryUsed, primaryOffset, secondaryOffset, nowOffset, permission) = scenarios[demoStepIndex]
            demoStepIndex += 1
            let simulatedNow = base + nowOffset
            demoNow = simulatedNow
            var response: [String: Any] = [
                "accountId": "synthetic-demo-account",
                "spendControlReached": false,
                "rateLimitReachedType": NSNull(),
                "rateLimits": [
                    "primary": ["usedPercent": primaryUsed, "windowDurationMins": 300, "resetsAt": base + primaryOffset],
                    "secondary": ["usedPercent": secondaryUsed, "windowDurationMins": 10_080, "resetsAt": base + secondaryOffset],
                ],
            ]
            if let permission { response["ordinaryUsageAllowed"] = permission }
            guard let value = UsageSnapshot(response, fetchedAt: Date(timeIntervalSince1970: simulatedNow), receivedUptime: ProcessInfo.processInfo.systemUptime) else {
                recordDemoScenario(name, availability: "snapshot-invalid", canResume: false, resetPopup: false, snapshotValid: false)
                return
            }
            let didPresentReset = acceptSnapshot(value)
            showPopover()
            let decision = currentDecision()
            recordDemoScenario(name, availability: "\(decision.availability)", canResume: decision.canResume, resetPopup: didPresentReset, snapshotValid: true)
        }
        applyNext()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in applyNext() }
    }
    private func observeResets(_ value: UsageSnapshot, wasAvailable: Bool, accountChanged: Bool) -> Bool {
        guard var tracker = resetTracker else { return false }
        do {
            try tracker.observe(value)
            let events = try tracker.claimPending()
            resetTracker = tracker
            resetTrackerLoadFailure = false
            guard !events.isEmpty else { return false }
            let activeIdea = resetIdeaPreview()
            celebrationPanel.present(events: events, snapshot: value, decision: currentDecision(), idea: activeIdea, language: language, relativeTo: status.button)
            if ResetSoundPolicy.shouldPlay(
                enabled: resetSoundEnabled,
                wasAvailable: wasAvailable,
                accountChanged: accountChanged,
                hasConfirmedReset: !events.isEmpty,
                isAvailable: currentDecision().canResume
            ) {
                ResetSoundPlayer.shared.play()
            }
            return true
        } catch {
            resetTracker = nil
            resetTrackerLoadFailure = true
            popoverController.setNotice(AppNotice.resetSaveFailed.text(in: language))
            return false
        }
    }
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else { showPopover() }
    }
    private func showPopover(forceDraft: Bool = false, focusIdeaID: UUID? = nil) {
        guard let button = status.button else { return }
        let isOpening = !popover.isShown
        if isOpening { selectQuoteForPopoverOpening() }
        render(forceDraft: forceDraft)
        if isOpening { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        if forceDraft { popoverController.focusDraftEditor() }
        else if let focusIdeaID { popoverController.focusIdea(id: focusIdeaID) }
    }
    private func scheduleDraftSave(_ text: String) {
        draftForFlush = text
        draftSaveTimer?.invalidate()
        draftSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.persistDraft(text)
        }
    }
    private func persistDraft(_ text: String) {
        do {
            try ideaStore.setDraft(text)
            draftPersistenceNeedsRetry = false
            popoverController.setNotice(AppNotice.draftSaved.text(in: language))
        } catch {
            draftPersistenceNeedsRetry = true
            popoverController.setNotice(AppNotice.draftSaveFailed.text(in: language))
        }
    }
    private func saveIdea(id: UUID?, text: String) -> String? {
        draftSaveTimer?.invalidate()
        draftSaveTimer = nil
        draftForFlush = text
        do {
            if let id { try ideaStore.updateIdea(id: id, text: text) }
            else { try ideaStore.saveIdea(text) }
            draftForFlush = ""
            draftPersistenceNeedsRetry = false
            render(forceDraft: true)
            return nil
        } catch IdeaStoreError.emptyIdea {
            return AppNotice.ideaEmpty.text(in: language)
        } catch {
            scheduleDraftSave(text)
            return AppNotice.ideaWriteFailed.text(in: language)
        }
    }
    private func deleteIdea(id: UUID) -> Bool {
        do { try ideaStore.deleteIdea(id: id); render(); return true }
        catch { return false }
    }
    private func exportIdeas() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "codex-ideas.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.ideaStore.exportJSON(to: url)
                self.popoverController.setNotice(AppNotice.ideasExported.text(in: self.language))
            } catch {
                self.popoverController.setNotice(AppNotice.ideasExportFailed.text(in: self.language))
            }
        }
    }
    @objc private func refresh() { client.refresh() }
    @objc private func quit() {
        draftSaveTimer?.invalidate()
        draftSaveTimer = nil
        if !ideaStoreLoadFailure,
           draftPersistenceNeedsRetry || draftForFlush != ideaStore.draft {
            do {
                try ideaStore.setDraft(draftForFlush)
                draftPersistenceNeedsRetry = false
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = language.text("灵感草稿尚未保存", "Your idea draft is not saved")
                alert.informativeText = language.text("草稿仍在编辑器中。继续退出会丢失尚未写入磁盘的内容。", "Your draft is still in the editor. Quitting now will lose changes not written to disk.")
                alert.addButton(withTitle: language.text("继续退出", "Quit"))
                alert.addButton(withTitle: language.text("返回编辑", "Keep editing"))
                guard alert.runModal() == .alertFirstButtonReturn else {
                    scheduleDraftSave(draftForFlush)
                    return
                }
            }
        }
        client.stop()
        NSApp.terminate(nil)
    }
    private func stateLabel(_ availability: QuotaAvailability) -> String {
        switch availability {
        case .available: return language.text("两个额度窗口已确认可用", "Both quota windows are available")
        case .limited: return language.text("额度受限，等待重置", "Quota is limited; waiting for reset")
        case .unknown: return language.text("额度状态待确认", "Quota status needs confirmation")
        case .confirming: return language.text("正在确认额度重置", "Confirming quota reset")
        case .restricted: return language.text("存在其他使用限制", "Another usage restriction is active")
        case .unavailable: return language.text("额度数据不可用", "Quota data is unavailable")
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate(); countdownTimer?.invalidate(); draftSaveTimer?.invalidate(); demoTimer?.invalidate()
        if !ideaStoreLoadFailure,
           draftPersistenceNeedsRetry || draftForFlush != ideaStore.draft {
            do { try ideaStore.setDraft(draftForFlush) } catch { /* final best-effort flush */ }
        }
        client.stop()
        if instanceLockDescriptor >= 0 { close(instanceLockDescriptor); instanceLockDescriptor = -1 }
    }
}

func renderPopoverPreview(to path: String, dark: Bool, language: AppLanguage) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let now = Date()
    let epoch = now.timeIntervalSince1970
    let response: [String: Any] = [
        "accountId": "preview-account",
        "ordinaryUsageAllowed": true,
        "spendControlReached": false,
        "rateLimits": [
            "primary": ["usedPercent": 32.0, "windowDurationMins": 300, "resetsAt": epoch + 2_400],
            "secondary": ["usedPercent": 100.0, "windowDurationMins": 10_080, "resetsAt": epoch + 518_400],
        ],
    ]
    let snapshot = UsageSnapshot(response, fetchedAt: now, receivedUptime: ProcessInfo.processInfo.systemUptime)!
    let decision = QuotaReducer.reduce(snapshot: snapshot, now: epoch, monotonicNow: ProcessInfo.processInfo.systemUptime, preferredWindow: .primary)
    let controller = QuotaPopoverViewController()
    controller.setDemoMode(CommandLine.arguments.contains("--demo"))
    let quoteID = CommandLine.arguments.firstIndex(of: "--quote-id").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
    let previewQuote = QuoteCatalog.quote(id: quoteID) ?? QuoteCatalog.quotes.first
    controller.update(snapshot: snapshot, decision: decision, error: nil, draft: "", ideas: [SavedIdea(text: "整理双额度恢复逻辑，并把提醒做成可靠的本地闭环。")], weekly: false, storageAvailable: true, language: language, quote: previewQuote)

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentViewController = controller
    window.contentView?.layoutSubtreeIfNeeded()
    controller.view.displayIfNeeded()
    let rect = controller.view.bounds
    guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: rect) else {
        throw NSError(domain: "CodexUsagePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法生成面板预览"])
    }
    controller.view.cacheDisplay(in: rect, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexUsagePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法编码预览图"])
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    window.close()
}

func writeQuoteLayoutMeasurements(to path: String) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let controller = QuotaPopoverViewController()
    var measurements: [QuoteLayoutMeasurement] = []
    for quote in QuoteCatalog.quotes {
        for language in AppLanguage.allCases {
            measurements.append(controller.measureQuoteLayout(quote: quote, language: language))
        }
    }
    guard measurements.count == 198,
          measurements.allSatisfy({
              $0.quoteTextHeight.isFinite && $0.quoteTextHeight > 0
                  && $0.attributionHeight.isFinite && $0.attributionHeight > 0
                  && $0.sourceButtonHeight.isFinite && $0.sourceButtonHeight > 0
                  && $0.quoteCardHeight.isFinite && $0.quoteCardHeight > 0
          }) else {
        throw NSError(domain: "CodexUsageLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: "原生语料测量未覆盖 99 条×2 种语言，或存在无效高度"])
    }

    let header = "quote_id,language,quote_characters,attribution_characters,quote_text_height_pt,attribution_height_pt,source_button_height_pt,quote_card_height_pt"
    let lines = measurements.map { row in
        [
            row.quoteID,
            row.language.rawValue,
            String(row.quoteCharacterCount),
            String(row.attributionCharacterCount),
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(row.quoteTextHeight)),
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(row.attributionHeight)),
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(row.sourceButtonHeight)),
            String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(row.quoteCardHeight)),
        ].joined(separator: ",")
    }
    let output = ([header] + lines).joined(separator: "\n") + "\n"
    try Data(output.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    let maxQuote = measurements.max { $0.quoteTextHeight < $1.quoteTextHeight }!
    let maxCard = measurements.max { $0.quoteCardHeight < $1.quoteCardHeight }!
    print("Measured 198 native quote layouts; max quote \(maxQuote.quoteTextHeight)pt (\(maxQuote.quoteID), \(maxQuote.language.rawValue)); max card \(maxCard.quoteCardHeight)pt (\(maxCard.quoteID), \(maxCard.language.rawValue)).")
}

private func previewLanguage() -> AppLanguage {
    guard let index = CommandLine.arguments.firstIndex(of: "--lang"), CommandLine.arguments.indices.contains(index + 1) else {
        return AppLanguage.initial()
    }
    return CommandLine.arguments[index + 1].lowercased().hasPrefix("en") ? .english : .chinese
}

if let index = CommandLine.arguments.firstIndex(of: "--preview-reset"), CommandLine.arguments.count > index + 1 {
    do {
        try ResetCelebrationPanel.renderPreview(
            to: CommandLine.arguments[index + 1],
            dark: CommandLine.arguments.contains("--dark"),
            weeklyStillExhausted: CommandLine.arguments.contains("--partial"),
            fiveHourStillExhausted: CommandLine.arguments.contains("--five-hour-still-exhausted"),
            permissionUnknown: CommandLine.arguments.contains("--unknown"),
            restricted: CommandLine.arguments.contains("--restricted"),
            awaitingConfirmation: CommandLine.arguments.contains("--awaiting"),
            bothWindowsExhausted: CommandLine.arguments.contains("--both-exhausted"),
            language: previewLanguage()
        )
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    exit(0)
} else if let index = CommandLine.arguments.firstIndex(of: "--preview-popover"), CommandLine.arguments.count > index + 1 {
    let dark = CommandLine.arguments.contains("--dark") || CommandLine.arguments.dropFirst(index + 2).contains("dark")
    do { try renderPopoverPreview(to: CommandLine.arguments[index + 1], dark: dark, language: previewLanguage()) }
    catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    exit(0)
} else if let index = CommandLine.arguments.firstIndex(of: "--preview-library"), CommandLine.arguments.count > index + 1 {
    do { try IdeaLibraryWindowController.renderPreview(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"), language: previewLanguage()) }
    catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    exit(0)
} else if let index = CommandLine.arguments.firstIndex(of: "--measure-quotes"), CommandLine.arguments.count > index + 1 {
    do { try writeQuoteLayoutMeasurements(to: CommandLine.arguments[index + 1]) }
    catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    exit(0)
} else if CommandLine.arguments.contains("--probe") {
    let client = UsageClient()
    client.onUpdate = { result in
        switch result {
        case .success(let snapshot):
            let decision = QuotaReducer.reduce(snapshot: snapshot, now: Date().timeIntervalSince1970, monotonicNow: ProcessInfo.processInfo.systemUptime)
            print("Live Codex quota read: state=\(decision.availability), canResume=\(decision.canResume)")
            client.stop(); exit(0)
        case .failure(let error): fputs(error.localizedDescription + "\n", stderr); exit(1)
        }
    }
    client.refresh(); RunLoop.main.run()
} else if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
    let path = CommandLine.arguments[index + 1]
    let examples: [(String, Double?)] = [
        ("100%", 100), ("99%", 99), ("50%", 50), ("34%", 34), ("1%", 1),
        ("0%", 0), ("04:59:59", 0), ("6d23:59:59", 0), ("—", nil), ("!", nil),
    ]
    let canvas = NSImage(size: NSSize(width: 760, height: 176), flipped: false) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 760, height: 176).fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        for y in [92, 4] { NSRect(x: 0, y: CGFloat(y), width: 760, height: 36).fill() }
        for (index, example) in examples.enumerated() {
            for dark in [false, true] {
                let y = CGFloat(140 - (index / 5) * 88 - (dark ? 40 : 0))
                let image = quotaStatusImage(label: example.0, fillPercent: example.1, dark: dark)
                image.draw(in: NSRect(x: CGFloat(20 + (index % 5) * 148), y: y, width: image.size.width, height: 20))
            }
        }
        return true
    }
    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
}
