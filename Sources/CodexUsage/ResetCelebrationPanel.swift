import AppKit
import UsageCore

struct ResetIdeaPreview {
    let text: String
    let savedIdeaID: UUID?
    let isDraft: Bool
}

private final class NonActivatingResetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ResetCelebrationPanel: NSObject {
    private let panel: NonActivatingResetPanel
    private let contentController: ResetCelebrationViewController

    override init() {
        panel = NonActivatingResetPanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 496), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentController = ResetCelebrationViewController()
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = contentController
    }

    var isVisible: Bool { panel.isVisible }
    var onOpenIdeas: ((UUID?, Bool) -> Void)? {
        get { contentController.onOpenIdeas }
        set { contentController.onOpenIdeas = newValue }
    }

    func setLanguage(_ language: AppLanguage) { contentController.setLanguage(language) }
    func setDemoMode(_ enabled: Bool) { contentController.setDemoMode(enabled) }

    func present(events: [ConfirmedResetEvent], snapshot: UsageSnapshot?, decision: QuotaDecision, idea: ResetIdeaPreview?, language: AppLanguage, relativeTo button: NSStatusBarButton?) {
        contentController.update(events: events, snapshot: snapshot, decision: decision, idea: idea, language: language, append: panel.isVisible)
        if !panel.isVisible {
            let frame = button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_024, height: 768)
            let x = min(max(frame.minX + 10, frame.maxX - panel.frame.width - 14), frame.maxX - panel.frame.width - 10)
            let y = min(max(frame.minY + 10, frame.maxY - panel.frame.height - 12), frame.maxY - panel.frame.height - 10)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        contentController.playPendingIdeaArrival()
    }

    func close() { panel.orderOut(nil) }
    func refresh(snapshot: UsageSnapshot?, decision: QuotaDecision, idea: ResetIdeaPreview?, language: AppLanguage) {
        contentController.update(events: [], snapshot: snapshot, decision: decision, idea: idea, language: language, append: true, animate: false)
    }

    static func renderPreview(to path: String, dark: Bool, weeklyStillExhausted: Bool, fiveHourStillExhausted: Bool = false, permissionUnknown: Bool = false, restricted: Bool = false, awaitingConfirmation: Bool = false, bothWindowsExhausted: Bool = false, language: AppLanguage = .chinese) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let now = Date()
        let epoch = now.timeIntervalSince1970
        let primaryExhausted = fiveHourStillExhausted || bothWindowsExhausted || awaitingConfirmation
        let secondaryExhausted = weeklyStillExhausted || bothWindowsExhausted
        let primaryReset = awaitingConfirmation ? epoch - 1 : epoch + 18_000
        let response: [String: Any] = [
            "accountId": "preview-account",
            "ordinaryUsageAllowed": permissionUnknown ? NSNull() : true,
            "spendControlReached": restricted,
            "rateLimits": [
                "primary": ["usedPercent": primaryExhausted ? 100.0 : 12.0, "windowDurationMins": 300, "resetsAt": primaryReset],
                "secondary": ["usedPercent": secondaryExhausted ? 100.0 : 34.0, "windowDurationMins": 10_080, "resetsAt": epoch + (secondaryExhausted ? 500_000 : 604_800)],
            ],
        ]
        guard let snapshot = UsageSnapshot(response, fetchedAt: now, receivedUptime: ProcessInfo.processInfo.systemUptime) else {
            throw NSError(domain: "CodexUsagePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法建立额度预览数据"])
        }
        let decision = QuotaReducer.reduce(snapshot: snapshot, now: epoch, monotonicNow: ProcessInfo.processInfo.systemUptime)
        let resetWindow: QuotaWindowKind = fiveHourStillExhausted ? .secondary : .primary
        let event = ConfirmedResetEvent(id: "preview-reset", window: resetWindow, durationMinutes: resetWindow == .primary ? 300 : 10_080, previousResetAt: epoch - 1, newResetAt: epoch + 18_000, detectedAt: now)
        let controller = ResetCelebrationViewController()
        controller.setDemoMode(CommandLine.arguments.contains("--demo"))
        let previewEvents = awaitingConfirmation ? [] : [event]
        controller.update(events: previewEvents, snapshot: snapshot, decision: decision, idea: ResetIdeaPreview(text: "把双额度恢复状态和提醒打磨完整。", savedIdeaID: UUID(), isDraft: false), language: language, append: false, reduceMotionOverride: true)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 392, height: 496), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            throw NSError(domain: "CodexUsagePreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法生成重置提醒预览"])
        }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CodexUsagePreview", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法编码重置提醒预览"])
        }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        window.close()
    }
}

private final class ResetCelebrationViewController: NSViewController {
    var onOpenIdeas: ((UUID?, Bool) -> Void)?
    private let starfield = StarfieldAnimationView(frame: NSRect(x: 0, y: 0, width: 356, height: 238))
    private let demoLabel = NSTextField(labelWithString: "演示数据")
    private let titleLabel = NSTextField(wrappingLabelWithString: "能量就绪，创造继续")
    private let eventsLabel = NSTextField(wrappingLabelWithString: "")
    private let stateLabel = NSTextField(wrappingLabelWithString: "")
    private let ideaLabel = NSTextField(wrappingLabelWithString: "")
    private let ideaCard = ResetIdeaCardView()
    private let openIdeasButton = NSButton(title: "打开灵感", target: nil, action: nil)
    private let closeButton = NSButton(title: "知道了", target: nil, action: nil)
    private var currentEvents: [ConfirmedResetEvent] = []
    private var language = AppLanguage.initial()
    private var canResume = false
    private var ideaPreview: ResetIdeaPreview?
    private var celebratedResetIDs = Set<String>()
    private var hasPendingIdeaArrival = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 392, height: 496))
        root.appearance = NSAppearance(named: .darkAqua)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 10/255, green: 16/255, blue: 31/255, alpha: 1).cgColor
        let spaceGradient = CAGradientLayer()
        spaceGradient.frame = root.bounds
        spaceGradient.colors = [
            NSColor(srgbRed: 18/255, green: 26/255, blue: 52/255, alpha: 1).cgColor,
            NSColor(srgbRed: 10/255, green: 16/255, blue: 31/255, alpha: 1).cgColor,
        ]
        spaceGradient.startPoint = CGPoint(x: 0.5, y: 1)
        spaceGradient.endPoint = CGPoint(x: 0.5, y: 0)
        root.layer?.addSublayer(spaceGradient)
        root.layer?.borderColor = NSColor(srgbRed: 0.23, green: 0.29, blue: 0.40, alpha: 1).cgColor
        root.layer?.borderWidth = 0.8
        root.layer?.cornerRadius = 18
        root.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -13),
        ])

        starfield.wantsLayer = true
        starfield.heightAnchor.constraint(equalToConstant: 238).isActive = true
        starfield.widthAnchor.constraint(equalToConstant: 356).isActive = true
        stack.addArrangedSubview(starfield)

        demoLabel.font = .systemFont(ofSize: 10, weight: .bold)
        demoLabel.textColor = .systemOrange
        demoLabel.isHidden = true
        demoLabel.setAccessibilityLabel("演示数据")
        stack.addArrangedSubview(demoLabel)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        eventsLabel.font = .systemFont(ofSize: 10, weight: .medium)
        eventsLabel.alignment = .center
        eventsLabel.textColor = .codexSecondaryLabel
        eventsLabel.maximumNumberOfLines = 2
        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.alignment = .center
        stateLabel.textColor = .codexSecondaryLabel
        stateLabel.maximumNumberOfLines = 3
        ideaLabel.alignment = .center
        ideaLabel.maximumNumberOfLines = 3
        ideaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ideaLabel.widthAnchor.constraint(equalToConstant: 326).isActive = true
        ideaLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        ideaCard.widthAnchor.constraint(equalToConstant: 356).isActive = true
        ideaCard.heightAnchor.constraint(equalToConstant: 74).isActive = true
        ideaCard.setContentHuggingPriority(.required, for: .vertical)
        ideaCard.setContentCompressionResistancePriority(.required, for: .vertical)
        ideaCard.addArrangedSubview(ideaLabel)
        for label in [titleLabel, stateLabel, eventsLabel] {
            label.widthAnchor.constraint(equalToConstant: 356).isActive = true
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            stack.addArrangedSubview(label)
        }
        stack.addArrangedSubview(ideaCard)

        let actions = NSStackView(views: [openIdeasButton, closeButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        openIdeasButton.bezelStyle = .rounded
        closeButton.bezelStyle = .rounded
        openIdeasButton.target = self
        openIdeasButton.action = #selector(openIdeas)
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        stack.addArrangedSubview(actions)
        self.view = root
        applyLanguage()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        if isViewLoaded { applyLanguage() }
    }

    func setDemoMode(_ enabled: Bool) {
        _ = view
        demoLabel.isHidden = !enabled
    }

    func update(events: [ConfirmedResetEvent], snapshot: UsageSnapshot?, decision: QuotaDecision, idea: ResetIdeaPreview?, language: AppLanguage, append: Bool, reduceMotionOverride: Bool? = nil, animate: Bool = true) {
        _ = view
        self.language = language
        if !append { currentEvents.removeAll() }
        for event in events {
            currentEvents.removeAll { $0.window == event.window }
            currentEvents.append(event)
        }
        canResume = decision.canResume
        ideaPreview = idea
        var newConfirmedReset = false
        for event in events where celebratedResetIDs.insert(event.id).inserted {
            newConfirmedReset = true
        }
        hasPendingIdeaArrival = animate
            && newConfirmedReset
            && decision.canResume
            && idea.map { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
        let records = currentEvents.map { event in
            "\(language.quotaShortName(event.window)) · \(language.time(event.detectedAt))"
        }
        eventsLabel.stringValue = records.isEmpty
            ? ""
            : language.text("重置记录：\(records.joined(separator: "、"))", "Reset record: \(records.joined(separator: ", "))")

        var exhausted: [(QuotaWindowKind, UsageWindow)] = []
        if let primary = snapshot?.primary, primary.isExhausted { exhausted.append((.primary, primary)) }
        if let secondary = snapshot?.secondary, secondary.isExhausted { exhausted.append((.secondary, secondary)) }
        if !exhausted.isEmpty {
            stateLabel.stringValue = exhausted.map { kind, window in
                let title = language.quotaWindowTitle(kind)
                guard let reset = window.resetsAt else { return language.text("\(title)仍已耗尽，重置时间未知", "\(title) remains exhausted; reset time is unknown.") }
                if reset <= Date().timeIntervalSince1970 {
                    return language.text("\(title)仍已耗尽 · 重置时间已到，等待服务端确认", "\(title) remains exhausted · reset time passed; waiting for server confirmation")
                }
                return language.text("\(title)仍已耗尽 · \(language.resetTime(Int(ceil(reset - Date().timeIntervalSince1970)), date: Date(timeIntervalSince1970: reset)))", "\(title) remains exhausted · \(language.resetTime(Int(ceil(reset - Date().timeIntervalSince1970)), date: Date(timeIntervalSince1970: reset)))")
            }.joined(separator: "\n")
            let blockedNames = exhausted.map { language.quotaShortName($0.0) }.joined(separator: language == .chinese ? "、" : ", ")
            titleLabel.stringValue = language.text("\(blockedNames)额度仍受限", "\(blockedNames) quota still limited")
        } else if decision.canResume {
            let fiveHour = snapshot?.primary?.remainingText ?? language.text("未知", "unknown")
            let sevenDay = snapshot?.secondary?.remainingText ?? language.text("未知", "unknown")
            stateLabel.stringValue = language.text("5 小时 \(fiveHour) · 7 天 \(sevenDay) · 服务端已确认可用", "5-hour \(fiveHour) · 7-day \(sevenDay) · server confirms availability")
            titleLabel.stringValue = language.text("能量就绪，创造继续", "Ready to create again.")
        } else {
            stateLabel.stringValue = language.reason(decision.reason)
            titleLabel.stringValue = decision.availability == .restricted
                ? language.text("仍有其他使用限制", "Another usage restriction is active")
                : language.text("可用状态待确认", "Availability needs confirmation")
        }

        eventsLabel.textColor = .codexSecondaryLabel

        if decision.canResume, let idea, !idea.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let excerpt = idea.text.prefix(50)
            if idea.isDraft {
                ideaLabel.stringValue = language.text("刚才写下的草稿，可以接着完善。\n“\(excerpt)\(idea.text.count > 50 ? "…" : "")”", "Pick up the draft you were writing.\n“\(excerpt)\(idea.text.count > 50 ? "…" : "")”")
            } else {
                ideaLabel.stringValue = language.text("刚才记下的灵感，可以开始实施了。\n“\(excerpt)\(idea.text.count > 50 ? "…" : "")”", "Your saved idea is ready to put into motion.\n“\(excerpt)\(idea.text.count > 50 ? "…" : "")”")
            }
            ideaCard.isHidden = false
        } else {
            ideaLabel.stringValue = ""
            ideaCard.isHidden = true
        }
        openIdeasButton.isHidden = false
        starfield.presentationState = decision.canResume ? .fullAvailable : .partialOrUnknown
        starfield.reduceMotionOverride = reduceMotionOverride
        applyLanguage()
        view.layoutSubtreeIfNeeded()
        if animate { starfield.refreshMotionPreference() }
    }

    func playPendingIdeaArrival() {
        guard hasPendingIdeaArrival else { return }
        hasPendingIdeaArrival = false
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        starfield.pulseCoreOnce()
        ideaCard.playArrivalGlint()
    }

    private func applyLanguage() {
        demoLabel.stringValue = language.text("演示数据", "DEMO DATA")
        if !canResume {
            openIdeasButton.title = language.text("记录灵感", "Save an idea")
        } else if ideaPreview?.savedIdeaID != nil && ideaPreview?.isDraft == false {
            openIdeasButton.title = language.text("打开灵感", "Open idea")
        } else if ideaPreview?.isDraft == true {
            openIdeasButton.title = language.text("继续草稿", "Continue draft")
        } else {
            openIdeasButton.title = language.text("写下灵感", "Write an idea")
        }
        closeButton.title = language.text("知道了", "Got it")
        for button in [openIdeasButton, closeButton] { button.setAccessibilityLabel(button.title) }
    }

    @objc private func openIdeas() {
        let canOpenSavedIdea = canResume && ideaPreview?.savedIdeaID != nil && ideaPreview?.isDraft == false
        onOpenIdeas?(canOpenSavedIdea ? ideaPreview?.savedIdeaID : nil, !canOpenSavedIdea)
    }
    @objc private func closePanel() { view.window?.orderOut(nil) }
}

private final class ResetIdeaCardView: NSStackView {
    private let edgeGlint = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .centerX
        edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        spacing = 0
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.7
        edgeGlint.fillColor = NSColor.clear.cgColor
        edgeGlint.lineWidth = 1.6
        edgeGlint.lineCap = .round
        edgeGlint.strokeEnd = 0
        layer?.addSublayer(edgeGlint)
        updatePalette()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePalette()
    }

    override func layout() {
        super.layout()
        edgeGlint.frame = bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 12, y: bounds.height - 0.8))
        path.addLine(to: CGPoint(x: max(12, bounds.width - 12), y: bounds.height - 0.8))
        edgeGlint.path = path
    }

    func playArrivalGlint() {
        guard let layer else { return }
        edgeGlint.removeAllAnimations()
        edgeGlint.strokeEnd = 0
        edgeGlint.opacity = 0

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.42
        draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        draw.isRemovedOnCompletion = true
        edgeGlint.add(draw, forKey: "ideaArrivalDraw")

        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = [0, 0.95, 0.32, 0]
        glow.keyTimes = [0, 0.35, 0.72, 1]
        glow.duration = 0.78
        glow.beginTime = CACurrentMediaTime() + 0.12
        glow.isRemovedOnCompletion = true
        edgeGlint.add(glow, forKey: "ideaArrivalGlow")

        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = 0.0
        shadow.toValue = 0.42
        shadow.duration = 0.26
        shadow.autoreverses = true
        shadow.beginTime = CACurrentMediaTime() + 0.18
        shadow.isRemovedOnCompletion = true
        edgeGlint.shadowColor = NSColor.controlAccentColor.codexCGColor(for: effectiveAppearance)
        edgeGlint.shadowRadius = 5
        edgeGlint.add(shadow, forKey: "ideaArrivalShadow")
        layer.setNeedsDisplay()
    }

    private func updatePalette() {
        layer?.backgroundColor = NSColor.codexEditorBackground.codexCGColor(for: effectiveAppearance)
        layer?.borderColor = NSColor.codexSecondaryLabel.withAlphaComponent(0.22).codexCGColor(for: effectiveAppearance)
        edgeGlint.strokeColor = NSColor.controlAccentColor.codexCGColor(for: effectiveAppearance)
        edgeGlint.shadowColor = NSColor.controlAccentColor.codexCGColor(for: effectiveAppearance)
    }
}
