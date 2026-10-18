import AppKit
import UsageCore

final class IdeaLibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onEditIdea: ((UUID) -> Void)?
    var onNewIdea: (() -> Void)?
    var onCopyIdea: ((String) -> Void)?
    var onDeleteIdea: ((UUID) -> Bool)?

    private let countLabel = NSTextField(labelWithString: "灵感匣")
    private let tableView = NSTableView()
    private let detailTitleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailDateLabel = NSTextField(labelWithString: "")
    private let detailTextView = NSTextView()
    private let noticeLabel = NSTextField(labelWithString: "")
    private let newIdeaButton = NSButton(title: "新建灵感", target: nil, action: nil)
    private let editButton = NSButton(title: "在记录区编辑", target: nil, action: nil)
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    private var ideas: [SavedIdea] = []
    private var language = AppLanguage.initial()
    private var selectedID: UUID?
    private var applyingSelection = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 420)
        window.title = language.text("本地灵感库", "Local Idea Library")
        buildView()
    }

    required init?(coder: NSCoder) { nil }

    func show(ideas: [SavedIdea], language: AppLanguage) {
        update(ideas: ideas, language: language)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(ideas: [SavedIdea], language: AppLanguage) {
        let languageChanged = self.language != language
        let ideasChanged = self.ideas != ideas
        guard languageChanged || ideasChanged else { return }
        let selection = selectedID
        self.ideas = ideas
        self.language = language
        applyLanguage()
        tableView.reloadData()
        let nextID = selection.flatMap { id in ideas.contains(where: { $0.id == id }) ? id : nil } ?? ideas.first?.id
        applyingSelection = true
        if let nextID, let row = ideas.firstIndex(where: { $0.id == nextID }) {
            selectedID = nextID
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            selectedID = nil
            tableView.deselectAll(nil)
        }
        applyingSelection = false
        if languageChanged || selectedID != selection { renderSelection() }
        else if let selectedID, let idea = ideas.first(where: { $0.id == selectedID }) {
            renderSelection(idea: idea)
        } else {
            renderSelection()
        }
    }

    private func buildView() {
        guard let window else { return }
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detail)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            sidebar.widthAnchor.constraint(equalToConstant: 238),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 14),
            divider.topAnchor.constraint(equalTo: sidebar.topAnchor),
            divider.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 18),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            detail.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
        ])

        countLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        newIdeaButton.target = self
        newIdeaButton.action = #selector(createIdea)
        newIdeaButton.bezelStyle = .rounded
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("idea"))
        tableColumn.title = ""
        tableColumn.width = 222
        tableColumn.minWidth = 180
        tableView.addTableColumn(tableColumn)
        tableView.frame = NSRect(x: 0, y: 0, width: 222, height: 0)
        tableView.autoresizingMask = [.width]
        tableView.headerView = nil
        tableView.rowHeight = 66
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.setAccessibilityLabel(language.text("已保存的灵感", "Saved ideas"))
        let tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .noBorder
        tableScroll.drawsBackground = false
        tableScroll.documentView = tableView
        sidebar.addSubview(countLabel)
        sidebar.addSubview(newIdeaButton)
        sidebar.addSubview(tableScroll)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        newIdeaButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            countLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            countLabel.topAnchor.constraint(equalTo: sidebar.topAnchor),
            newIdeaButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            newIdeaButton.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            tableScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: newIdeaButton.bottomAnchor, constant: 12),
            tableScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        detailTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        detailTitleLabel.maximumNumberOfLines = 2
        detailTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        detailDateLabel.font = .systemFont(ofSize: 11)
        detailDateLabel.textColor = .codexSecondaryLabel
        let header = NSStackView(views: [detailTitleLabel, detailDateLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.backgroundColor = .clear
        detailTextView.font = .systemFont(ofSize: 14)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.minSize = NSSize(width: 0, height: 0)
        detailTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainerInset = NSSize(width: 2, height: 8)
        detailTextView.textContainer?.widthTracksTextView = true
        let detailScroll = NSScrollView()
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.borderType = .noBorder
        detailScroll.drawsBackground = false
        detailScroll.documentView = detailTextView

        let actions = NSStackView(views: [editButton, copyButton, deleteButton, noticeLabel])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        editButton.bezelStyle = .rounded
        copyButton.bezelStyle = .rounded
        deleteButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editSelectedIdea)
        copyButton.target = self
        copyButton.action = #selector(copySelectedIdea)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedIdea)
        noticeLabel.font = .systemFont(ofSize: 11)
        noticeLabel.textColor = .codexSecondaryLabel

        detail.addSubview(header)
        detail.addSubview(detailScroll)
        detail.addSubview(actions)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            header.topAnchor.constraint(equalTo: detail.topAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            detailScroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -14),
            actions.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            actions.trailingAnchor.constraint(lessThanOrEqualTo: detail.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
        ])
        applyLanguage()
        renderSelection()
    }

    private func applyLanguage() {
        guard isWindowLoaded else { return }
        window?.title = language.text("本地灵感库", "Local Idea Library")
        countLabel.stringValue = language == .chinese ? "灵感匣（\(ideas.count)）" : "Idea box (\(ideas.count))"
        newIdeaButton.title = language.text("新建灵感", "New idea")
        editButton.title = language.text("在记录区编辑", "Edit in capture area")
        copyButton.title = language.text("复制", "Copy")
        deleteButton.title = language.text("删除", "Delete")
        tableView.setAccessibilityLabel(language.text("已保存的灵感", "Saved ideas"))
        for button in [newIdeaButton, editButton, copyButton, deleteButton] {
            button.setAccessibilityLabel(button.title)
        }
    }

    private func renderSelection(idea: SavedIdea? = nil) {
        guard let idea = idea ?? selectedID.flatMap({ id in ideas.first(where: { $0.id == id }) }) else {
            detailTitleLabel.stringValue = language.text("选择一条灵感", "Choose an idea")
            detailDateLabel.stringValue = ""
            detailTextView.string = language.text("在主面板底部记录新想法。你保存的内容只保存在本机。", "Write a new idea in the menu-bar capture area. Saved ideas stay on this Mac.")
            editButton.isEnabled = false
            copyButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        detailTitleLabel.stringValue = String(idea.text.prefix(64)) + (idea.text.count > 64 ? "…" : "")
        detailDateLabel.stringValue = language.dateTime(idea.updatedAt)
        detailTextView.string = idea.text
        editButton.isEnabled = true
        copyButton.isEnabled = true
        deleteButton.isEnabled = true
        noticeLabel.stringValue = ""
    }

    func numberOfRows(in tableView: NSTableView) -> Int { ideas.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard ideas.indices.contains(row) else { return nil }
        let idea = ideas[row]
        let cell = NSTableCellView()
        let title = NSTextField(wrappingLabelWithString: String(idea.text.prefix(72)) + (idea.text.count > 72 ? "…" : ""))
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        let date = NSTextField(labelWithString: language.time(idea.updatedAt))
        date.font = .systemFont(ofSize: 10)
        date.textColor = .codexSecondaryLabel
        let stack = NSStackView(views: [title, date])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection else { return }
        let row = tableView.selectedRow
        selectedID = ideas.indices.contains(row) ? ideas[row].id : nil
        renderSelection()
    }

    @objc private func createIdea() {
        close()
        onNewIdea?()
    }

    @objc private func editSelectedIdea() {
        guard let selectedID else { return }
        close()
        onEditIdea?(selectedID)
    }

    @objc private func copySelectedIdea() {
        guard let selectedID, let idea = ideas.first(where: { $0.id == selectedID }) else { return }
        onCopyIdea?(idea.text)
        noticeLabel.stringValue = language.text("已复制", "Copied")
    }

    @objc private func deleteSelectedIdea() {
        guard let selectedID, let idea = ideas.first(where: { $0.id == selectedID }) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.text("删除这条灵感？", "Delete this idea?")
        alert.informativeText = String(idea.text.prefix(120))
        alert.addButton(withTitle: language.text("删除", "Delete"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn,
              onDeleteIdea?(selectedID) == true else { return }
        noticeLabel.stringValue = language.text("已删除", "Deleted")
    }

    static func renderPreview(to path: String, dark: Bool, language: AppLanguage) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let controller = IdeaLibraryWindowController()
        let short = SavedIdea(text: "恢复后回到记录的想法，继续做完最小可验证的一步。")
        let long = SavedIdea(text: "先用 99 条双语语料检查名言卡片的实际高度，再用当前仍受限、部分恢复和完全恢复三个状态核对菜单栏提示。记录和计时器是本地信息；额度是否恢复仍以 Codex 服务端对 5 小时和 7 天窗口的回包为准。")
        let recent = SavedIdea(text: "把名言、随手记录和恢复后的回访连成一次轻量体验。")
        controller.update(ideas: [recent, long, short], language: language)
        controller.selectedID = long.id
        controller.applyingSelection = true
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        controller.applyingSelection = false
        controller.renderSelection(idea: long)
        controller.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        guard let content = controller.window?.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw NSError(domain: "CodexUsagePreview", code: 6, userInfo: [NSLocalizedDescriptionKey: "无法生成灵感库预览"])
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CodexUsagePreview", code: 7, userInfo: [NSLocalizedDescriptionKey: "无法编码灵感库预览"])
        }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        controller.close()
    }
}
