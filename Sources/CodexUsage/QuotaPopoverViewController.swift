import AppKit
import UsageCore

struct QuoteLayoutMeasurement {
    let quoteID: String
    let language: AppLanguage
    let quoteCharacterCount: Int
    let attributionCharacterCount: Int
    let quoteTextHeight: CGFloat
    let attributionHeight: CGFloat
    let sourceButtonHeight: CGFloat
    let quoteCardHeight: CGFloat
}

final class QuotaPopoverViewController: NSViewController, NSTextViewDelegate {
    var onDraftChanged: ((String) -> Void)?
    var onSaveIdea: ((UUID?, String) -> String?)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onClose: (() -> Void)?
    var onExportIdeas: (() -> Void)?
    var onOpenIdeaLibrary: (() -> Void)?
    var onSelectWindow: ((Bool) -> Void)?
    var onSelectLanguage: ((AppLanguage) -> Void)?
    var onOpenQuoteSource: ((URL) -> Void)?
    var onResetSoundChanged: ((Bool) -> Void)?
    var onPreviewResetSound: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Codex 使用额度")
    private let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let demoBadge = NSTextField(labelWithString: "演示数据 · DEMO DATA")
    private let stateLabel = NSTextField(wrappingLabelWithString: "正在读取额度…")
    private let primaryRow = QuotaWindowRow(kind: .primary)
    private let secondaryRow = QuotaWindowRow(kind: .secondary)
    private let draftTextView = IdeaEditorTextView()
    private let saveButton = NSButton(title: "保存灵感 / Save idea", target: nil, action: nil)
    private let saveStatusLabel = NSTextField(labelWithString: "")
    private let quoteTextLabel = NSTextField(wrappingLabelWithString: "")
    private let quoteAttributionLabel = NSTextField(wrappingLabelWithString: "")
    private let quoteSourceButton = NSButton(title: "出处", target: nil, action: nil)
    private var quoteCard: CodexCardStackView?
    private let promptLabel = NSTextField(labelWithString: "")
    private let ideasTitleLabel = NSTextField(labelWithString: "")
    private let libraryButton = NSButton(title: "灵感库", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新额度", target: nil, action: nil)
    private let exportButton = NSButton(title: "导出灵感", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出", target: nil, action: nil)
    private let resetSoundToggle = NSButton(checkboxWithTitle: "重置提示音", target: nil, action: nil)
    private let previewResetSoundButton = NSButton(title: "试听", target: nil, action: nil)
    private let ideaList = NSStackView()
    private var displayedIdeas: [SavedIdea] = []
    private var editingIdeaID: UUID?
    private var panelScrollView: NSScrollView?
    private var documentContentView: NSView?
    private var bodyStack: NSStackView?
    private var initialScrollPositionSet = false
    private var language = AppLanguage.initial()
    private var quote: FamousQuote?

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 540))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        languagePicker.addItems(withTitles: AppLanguage.allCases.map(\.settingsTitle))
        languagePicker.target = self
        languagePicker.action = #selector(languageSelectionChanged)
        languagePicker.setContentHuggingPriority(.required, for: .horizontal)
        languagePicker.setAccessibilityLabel(language.text("界面语言", "Interface language"))
        let titleRow = NSStackView(views: [titleLabel, languagePicker])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleRow)

        let scroll = NSScrollView(frame: root.bounds)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        root.addSubview(scroll)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 328, height: 560))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 328),
        ])
        scroll.documentView = content
        panelScrollView = scroll
        documentContentView = content
        bodyStack = stack
        NSLayoutConstraint.activate([
            titleRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            titleRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            titleRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
        ])
        demoBadge.font = .systemFont(ofSize: 10, weight: .bold)
        demoBadge.textColor = .systemOrange
        demoBadge.isHidden = true
        demoBadge.widthAnchor.constraint(equalToConstant: 328).isActive = true
        stateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stateLabel.widthAnchor.constraint(equalToConstant: 328).isActive = true
        stateLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        stateLabel.textColor = .codexSecondaryLabel
        stateLabel.maximumNumberOfLines = 2
        stateLabel.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(demoBadge)
        stack.addArrangedSubview(stateLabel)

        primaryRow.onSelect = { [weak self] in self?.onSelectWindow?(false) }
        secondaryRow.onSelect = { [weak self] in self?.onSelectWindow?(true) }

        let rows = NSStackView(views: [primaryRow, secondaryRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 7
        rows.widthAnchor.constraint(equalToConstant: 328).isActive = true
        stack.addArrangedSubview(rows)

        let quoteBox = CodexCardStackView()
        quoteCard = quoteBox
        quoteBox.orientation = .vertical
        quoteBox.alignment = .leading
        quoteBox.spacing = 5
        quoteBox.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        quoteBox.wantsLayer = true
        quoteBox.layer?.backgroundColor = NSColor.codexCardBackground.codexCGColor(for: root.effectiveAppearance)
        quoteBox.layer?.cornerRadius = 9
        quoteTextLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        quoteAttributionLabel.font = .systemFont(ofSize: 9)
        quoteAttributionLabel.textColor = .codexSecondaryLabel
        quoteSourceButton.bezelStyle = .inline
        quoteSourceButton.target = self
        quoteSourceButton.action = #selector(quoteSourceTapped)
        let quoteFooter = NSStackView(views: [quoteAttributionLabel, quoteSourceButton])
        quoteFooter.orientation = .horizontal
        quoteFooter.alignment = .centerY
        quoteFooter.spacing = 5
        quoteFooter.widthAnchor.constraint(equalToConstant: 304).isActive = true
        quoteTextLabel.widthAnchor.constraint(equalToConstant: 304).isActive = true
        quoteTextLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        quoteAttributionLabel.widthAnchor.constraint(equalToConstant: 234).isActive = true
        quoteAttributionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        quoteAttributionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteSourceButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        quoteBox.addArrangedSubview(quoteTextLabel)
        quoteBox.addArrangedSubview(quoteFooter)
        quoteBox.widthAnchor.constraint(equalToConstant: 328).isActive = true
        stack.addArrangedSubview(quoteBox)

        promptLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        promptLabel.widthAnchor.constraint(equalToConstant: 304).isActive = true
        promptLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let editorScroll = CodexEditorScrollView()
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.hasVerticalScroller = true
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        editorScroll.wantsLayer = true
        editorScroll.layer?.backgroundColor = NSColor.codexEditorBackground.codexCGColor(for: root.effectiveAppearance)
        editorScroll.layer?.cornerRadius = 8
        editorScroll.layer?.masksToBounds = true
        editorScroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        editorScroll.widthAnchor.constraint(equalToConstant: 304).isActive = true
        draftTextView.drawsBackground = false
        draftTextView.backgroundColor = .clear
        draftTextView.minSize = NSSize(width: 0, height: 60)
        draftTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        draftTextView.isVerticallyResizable = true
        draftTextView.isHorizontallyResizable = false
        draftTextView.autoresizingMask = [.width]
        draftTextView.textContainer?.widthTracksTextView = true
        draftTextView.textContainerInset = NSSize(width: 10, height: 7)
        draftTextView.font = .systemFont(ofSize: 13)
        draftTextView.setAccessibilityLabel(language.text("灵感草稿", "Idea draft"))
        draftTextView.onCommandEnter = { [weak self] in self?.saveTapped() }
        draftTextView.onEscape = { [weak self] in self?.onClose?() }
        draftTextView.delegate = self
        editorScroll.documentView = draftTextView

        let saveRow = NSStackView(views: [saveButton, saveStatusLabel])
        saveRow.orientation = .horizontal
        saveRow.alignment = .centerY
        saveRow.spacing = 8
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.bezelStyle = .rounded
        saveStatusLabel.font = .systemFont(ofSize: 10)
        saveStatusLabel.textColor = .codexSecondaryLabel
        saveRow.widthAnchor.constraint(equalToConstant: 304).isActive = true

        let captureCard = CodexCardStackView()
        captureCard.orientation = .vertical
        captureCard.alignment = .leading
        captureCard.spacing = 6
        captureCard.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        captureCard.wantsLayer = true
        captureCard.layer?.backgroundColor = NSColor.codexCardBackground.codexCGColor(for: root.effectiveAppearance)
        captureCard.layer?.cornerRadius = 11
        captureCard.translatesAutoresizingMaskIntoConstraints = false
        captureCard.addArrangedSubview(promptLabel)
        captureCard.addArrangedSubview(editorScroll)
        captureCard.addArrangedSubview(saveRow)
        root.addSubview(captureCard)
        NSLayoutConstraint.activate([
            captureCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            captureCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            captureCard.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: captureCard.topAnchor, constant: -8),
        ])

        ideasTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        ideasTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let ideasHeader = NSStackView(views: [ideasTitleLabel, libraryButton])
        ideasHeader.orientation = .horizontal
        ideasHeader.alignment = .centerY
        ideasHeader.spacing = 8
        ideasHeader.widthAnchor.constraint(equalToConstant: 328).isActive = true
        libraryButton.target = self
        libraryButton.action = #selector(openIdeaLibraryTapped)
        libraryButton.bezelStyle = .texturedRounded
        stack.addArrangedSubview(ideasHeader)
        ideaList.orientation = .vertical
        ideaList.alignment = .leading
        ideaList.spacing = 6
        ideaList.widthAnchor.constraint(equalToConstant: 328).isActive = true
        stack.addArrangedSubview(ideaList)

        let resetSoundRow = NSStackView(views: [resetSoundToggle, previewResetSoundButton])
        resetSoundRow.orientation = .horizontal
        resetSoundRow.alignment = .centerY
        resetSoundRow.spacing = 8
        resetSoundRow.widthAnchor.constraint(equalToConstant: 328).isActive = true
        resetSoundToggle.target = self
        resetSoundToggle.action = #selector(resetSoundChanged)
        resetSoundToggle.setAccessibilityLabel("重置成功提示音")
        previewResetSoundButton.target = self
        previewResetSoundButton.action = #selector(previewResetSound)
        previewResetSoundButton.bezelStyle = .texturedRounded
        stack.addArrangedSubview(resetSoundRow)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.bezelStyle = .texturedRounded
        exportButton.target = self
        exportButton.action = #selector(exportTapped)
        exportButton.bezelStyle = .texturedRounded
        quitButton.target = self
        quitButton.action = #selector(quitTapped)
        quitButton.bezelStyle = .texturedRounded
        footer.addArrangedSubview(refreshButton)
        footer.addArrangedSubview(exportButton)
        footer.addArrangedSubview(quitButton)
        stack.addArrangedSubview(footer)
        self.view = root
    }

    func measureQuoteLayout(quote: FamousQuote, language: AppLanguage) -> QuoteLayoutMeasurement {
        _ = view
        self.language = language
        self.quote = quote
        applyLanguage()
        renderQuote()
        view.layoutSubtreeIfNeeded()
        updateDocumentHeight()
        view.layoutSubtreeIfNeeded()
        quoteCard?.layoutSubtreeIfNeeded()

        let quoteTextHeight = ceil(quoteTextLabel.fittingSize.height)
        let attributionHeight = ceil(quoteAttributionLabel.fittingSize.height)
        let sourceButtonHeight = ceil(quoteSourceButton.fittingSize.height)
        let quoteCardHeight = ceil(quoteCard?.fittingSize.height ?? 0)
        return QuoteLayoutMeasurement(
            quoteID: quote.id,
            language: language,
            quoteCharacterCount: (language == .chinese ? quote.textChinese : quote.textEnglish).count,
            attributionCharacterCount: quoteAttributionLabel.stringValue.count,
            quoteTextHeight: quoteTextHeight,
            attributionHeight: attributionHeight,
            sourceButtonHeight: sourceButtonHeight,
            quoteCardHeight: quoteCardHeight
        )
    }

    func update(snapshot: UsageSnapshot?, decision: QuotaDecision, error: String?, draft: String, ideas: [SavedIdea], weekly: Bool, storageAvailable: Bool, language: AppLanguage, quote: FamousQuote?, forceDraft: Bool = false) {
        _ = self.view
        let languageChanged = self.language != language
        self.language = language
        if languageChanged { saveStatusLabel.stringValue = "" }
        self.quote = quote
        stateLabel.stringValue = statusSummary(snapshot: snapshot, decision: decision, error: error)
        stateLabel.textColor = decision.canResume ? .systemGreen : (decision.availability == .limited || decision.availability == .confirming ? .systemOrange : .codexSecondaryLabel)
        primaryRow.update(window: snapshot?.primary, now: Date(), language: language, selected: !weekly)
        secondaryRow.update(window: snapshot?.secondary, now: Date(), language: language, selected: weekly)
        draftTextView.isEditable = storageAvailable
        saveButton.isEnabled = storageAvailable
        let editing = draftTextView.window?.firstResponder === draftTextView
        if forceDraft || (!editing && draftTextView.string != draft) {
            draftTextView.string = draft
            editingIdeaID = nil
            saveButton.title = language.text("保存灵感", "Save idea")
        }
        if displayedIdeas != ideas || languageChanged {
            displayedIdeas = ideas
            renderIdeas()
        }
        applyLanguage()
        renderQuote()
        updateDocumentHeight()
        if !initialScrollPositionSet, let scroll = panelScrollView, let content = documentContentView {
            view.layoutSubtreeIfNeeded()
            let offset = max(0, content.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            initialScrollPositionSet = true
        }
    }

    func setNotice(_ text: String) {
        _ = self.view
        saveStatusLabel.stringValue = text
    }

    func focusDraftEditor() {
        _ = view
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.draftTextView.window?.makeFirstResponder(self.draftTextView)
        }
    }

    func focusIdea(id: UUID) {
        _ = view
        guard let idea = displayedIdeas.first(where: { $0.id == id }) else {
            focusDraftEditor()
            return
        }
        editingIdeaID = id
        draftTextView.string = idea.text
        saveButton.title = language.text("更新灵感", "Update idea")
        saveStatusLabel.stringValue = ""
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.draftTextView.window?.makeFirstResponder(self.draftTextView)
        }
    }

    func setDemoMode(_ enabled: Bool) {
        _ = self.view
        demoBadge.isHidden = !enabled
        demoBadge.stringValue = language.text("演示数据", "DEMO DATA")
        updateDocumentHeight()
    }

    func setResetSoundEnabled(_ enabled: Bool) {
        _ = self.view
        resetSoundToggle.state = enabled ? .on : .off
    }

    private func applyLanguage() {
        titleLabel.stringValue = language.text("Codex 使用额度", "Codex usage")
        let availableLanguages = AppLanguage.allCases
        if let index = availableLanguages.firstIndex(of: language) { languagePicker.selectItem(at: index) }
        languagePicker.setAccessibilityLabel(language.text("界面语言", "Interface language"))
        draftTextView.setAccessibilityLabel(language.text("灵感草稿", "Idea draft"))
        promptLabel.stringValue = language.text("有什么好想法，先记下来", "Have a good idea? Write it down.")
        ideasTitleLabel.stringValue = language.text("灵感匣（\(displayedIdeas.count)）", "Idea box (\(displayedIdeas.count))")
        refreshButton.title = language.text("刷新额度", "Refresh")
        exportButton.title = language.text("导出灵感", "Export ideas")
        quitButton.title = language.text("退出", "Quit")
        resetSoundToggle.title = language.text("重置提示音", "Reset chime")
        resetSoundToggle.setAccessibilityLabel(language.text("重置成功提示音", "Reset success sound"))
        previewResetSoundButton.title = language.text("试听", "Preview")
        libraryButton.title = language.text("灵感库", "Idea library")
        quoteSourceButton.title = language.text("出处", "Source")
        saveButton.title = editingIdeaID == nil ? language.text("保存灵感", "Save idea") : language.text("更新灵感", "Update idea")
    }

    private func renderQuote() {
        guard let quote else {
            quoteTextLabel.stringValue = ""
            quoteAttributionLabel.stringValue = ""
            quoteSourceButton.isEnabled = false
            return
        }
        quoteTextLabel.stringValue = language == .chinese ? quote.textChinese : quote.textEnglish
        let author = language == .chinese ? quote.authorChinese : quote.authorEnglish
        let work = language == .chinese ? quote.workChinese : quote.workEnglish
        let translation = language == .chinese ? quote.translationChinese : quote.translationEnglish
        let translatedMark = translation.map { " · \($0)" } ?? ""
        let locator = language == .chinese ? quote.locatorChinese : quote.locator
        quoteAttributionLabel.stringValue = "\(author) · \(work) · \(locator)\(translatedMark)"
        quoteTextLabel.setAccessibilityLabel(quoteTextLabel.stringValue)
        quoteAttributionLabel.setAccessibilityLabel(quoteAttributionLabel.stringValue)
        quoteSourceButton.isEnabled = true
    }

    private func updateDocumentHeight() {
        guard let content = documentContentView,
              let stack = bodyStack else { return }
        view.layoutSubtreeIfNeeded()
        let views = stack.arrangedSubviews
        let itemHeight = views.reduce(CGFloat.zero) { $0 + ceil($1.fittingSize.height) }
        let gaps = stack.spacing * CGFloat(max(0, views.count - 1))
        // Keep the document at its intrinsic content height when it fits. Stretching
        // it to the viewport makes AppKit distribute spare space inside the stack.
        let height = max(1, ceil(itemHeight + gaps + 32))
        if abs(content.frame.height - height) > 1 {
            content.setFrameSize(NSSize(width: 328, height: height))
            view.layoutSubtreeIfNeeded()
        }
    }

    private func statusSummary(snapshot: UsageSnapshot?, decision: QuotaDecision, error: String?) -> String {
        if let error { return error }
        guard decision.availability == .confirming, let snapshot else { return language.reason(decision.reason) }
        let now = Date().timeIntervalSince1970
        let awaiting = QuotaWindowKind.allCases.filter { kind in
            guard let window = kind == .primary ? snapshot.primary : snapshot.secondary,
                  window.isExhausted,
                  let reset = window.resetsAt else { return false }
            return reset <= now
        }
        if !awaiting.isEmpty {
            let names = awaiting.map { language.quotaShortName($0) }.joined(separator: language == .chinese ? "、" : ", ")
            return language.text("\(names)重置时间已到，等待服务端确认", "\(names) reset time passed. Waiting for server confirmation.")
        }
        let exhaustedCount = [snapshot.primary, snapshot.secondary].compactMap { $0 }.filter(\.isExhausted).count
        if exhaustedCount > 0 {
            return language.text("额度仍在使用周期内；倒计时结束后将重新确认", "A quota window is still active. It will be checked again when the countdown ends.")
        }
        return language.reason(decision.reason)
    }

    func textDidChange(_ notification: Notification) {
        guard draftTextView.isEditable else { return }
        saveStatusLabel.stringValue = ""
        onDraftChanged?(draftTextView.string)
    }

    private func renderIdeas() {
        ideaList.arrangedSubviews.forEach { view in
            ideaList.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if displayedIdeas.isEmpty {
            let empty = NSTextField(labelWithString: language.text("保存的想法会留在这里", "Saved ideas stay here"))
            empty.font = .systemFont(ofSize: 10)
            empty.textColor = .codexSecondaryLabel
            ideaList.addArrangedSubview(empty)
            return
        }
        guard let idea = displayedIdeas.first else { return }
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let text = NSTextField(wrappingLabelWithString: idea.text)
        text.font = .systemFont(ofSize: 11)
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byTruncatingTail
        text.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let edit = NSButton(title: language.text("编辑", "Edit"), target: self, action: #selector(editIdea(_:)))
        edit.identifier = NSUserInterfaceItemIdentifier(idea.id.uuidString)
        edit.bezelStyle = .texturedRounded
        row.addArrangedSubview(text)
        row.addArrangedSubview(edit)
        row.widthAnchor.constraint(equalToConstant: 328).isActive = true
        ideaList.addArrangedSubview(row)
    }

    @objc private func languageSelectionChanged() {
        let languages = AppLanguage.allCases
        guard languages.indices.contains(languagePicker.indexOfSelectedItem) else { return }
        onSelectLanguage?(languages[languagePicker.indexOfSelectedItem])
    }
    @objc private func quoteSourceTapped() {
        guard let sourceURL = quote?.sourceURL else { return }
        onOpenQuoteSource?(sourceURL)
    }
    @objc private func saveTapped() {
        guard let error = onSaveIdea?(editingIdeaID, draftTextView.string) else {
            editingIdeaID = nil
            saveStatusLabel.stringValue = language.text("已保存", "Saved")
            return
        }
        saveStatusLabel.stringValue = error
    }
    @objc private func editIdea(_ sender: NSButton) {
        guard let id = sender.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let idea = displayedIdeas.first(where: { $0.id == id }) else { return }
        editingIdeaID = id
        draftTextView.string = idea.text
        saveButton.title = language.text("更新灵感", "Update idea")
        draftTextView.window?.makeFirstResponder(draftTextView)
    }
    @objc private func refreshTapped() { onRefresh?() }
    @objc private func exportTapped() { onExportIdeas?() }
    @objc private func openIdeaLibraryTapped() { onOpenIdeaLibrary?() }
    @objc private func resetSoundChanged() { onResetSoundChanged?(resetSoundToggle.state == .on) }
    @objc private func previewResetSound() { onPreviewResetSound?() }
    @objc private func quitTapped() { onQuit?() }
}

private final class CodexCardStackView: NSStackView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.codexCardBackground.codexCGColor(for: effectiveAppearance)
    }
}

private final class CodexEditorScrollView: NSScrollView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.codexEditorBackground.codexCGColor(for: effectiveAppearance)
    }
}

private final class IdeaEditorTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers == .command {
            onCommandEnter?()
            return
        }
        if event.keyCode == 53 && modifiers.isEmpty {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class QuotaWindowRow: NSView {
    private let titleLabel: NSTextField
    private let kind: QuotaWindowKind
    private let selectionButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "未知")
    private let resetLabel = NSTextField(labelWithString: "")
    var onSelect: (() -> Void)?

    init(kind: QuotaWindowKind) {
        self.kind = kind
        titleLabel = NSTextField(labelWithString: kind == .primary ? "5 小时额度" : "7 天额度")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.codexCardBackground.codexCGColor(for: effectiveAppearance)
        layer?.cornerRadius = 8
        selectionButton.target = self
        selectionButton.action = #selector(selectionTapped)
        selectionButton.setContentHuggingPriority(.required, for: .horizontal)
        let heading = NSStackView(views: [selectionButton, titleLabel, valueLabel])
        heading.orientation = .horizontal
        heading.distribution = .fill
        heading.alignment = .centerY
        heading.spacing = 6
        heading.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.alignment = .right
        resetLabel.font = .systemFont(ofSize: 10)
        resetLabel.textColor = .codexSecondaryLabel
        resetLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(heading)
        addSubview(resetLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 328),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            resetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            resetLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            resetLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    func updateAppearanceColors() {
        layer?.backgroundColor = NSColor.codexCardBackground.codexCGColor(for: effectiveAppearance)
    }

    func update(window: UsageWindow?, now: Date, language: AppLanguage, selected: Bool) {
        setAccessibilityElement(true)
        titleLabel.stringValue = language.quotaWindowTitle(kind)
        selectionButton.title = language.text("菜单栏", "Menu bar")
        selectionButton.state = selected ? .on : .off
        selectionButton.setAccessibilityLabel(language.text("在菜单栏显示\(titleLabel.stringValue)", "Show \(titleLabel.stringValue) in the menu bar"))
        selectionButton.setAccessibilityValue(selected ? language.text("已选择", "Selected") : language.text("未选择", "Not selected"))
        guard let window else {
            valueLabel.stringValue = language.text("未知", "Unknown")
            resetLabel.stringValue = language.text("尚未从服务端确认", "Not confirmed by the server yet")
            setAccessibilityLabel(language.text("\(titleLabel.stringValue)，额度未知。尚未从服务端确认", "\(titleLabel.stringValue): unknown. Not confirmed by the server yet."))
            return
        }
        valueLabel.stringValue = window.remainingText
        guard let reset = window.resetsAt else {
            resetLabel.stringValue = language.text("重置时间未知", "Reset time unknown")
            setAccessibilityLabel(language.text("\(titleLabel.stringValue)，剩余 \(window.remainingText)。重置时间未知", "\(titleLabel.stringValue), \(window.remainingText) remaining. Reset time unknown."))
            return
        }
        let date = Date(timeIntervalSince1970: reset)
        if window.isExhausted {
            if reset > now.timeIntervalSince1970 {
                let remaining = Int(ceil(reset - now.timeIntervalSince1970))
                resetLabel.stringValue = language.resetTime(remaining, date: date)
            } else {
                resetLabel.stringValue = language.text("重置时间已到，等待服务端确认", "Reset time passed. Waiting for server confirmation.")
            }
        } else {
            resetLabel.stringValue = language.text("重置时间：\(language.dateTime(date))", "Resets: \(language.dateTime(date))")
        }
        setAccessibilityLabel(language.text("\(titleLabel.stringValue)，剩余 \(window.remainingText)。\(resetLabel.stringValue)", "\(titleLabel.stringValue), \(window.remainingText) remaining. \(resetLabel.stringValue)"))
    }

    @objc private func selectionTapped() { onSelect?() }
}
