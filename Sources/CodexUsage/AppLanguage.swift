import Foundation
import UsageCore

enum AppLanguage: String, CaseIterable, Codable {
    case chinese = "zh-Hans"
    case english = "en"

    var settingsTitle: String { self == .chinese ? "中文" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }

    static func initial(defaults: UserDefaults = .standard) -> AppLanguage {
        if let stored = defaults.string(forKey: "codexUsage.language"), let language = AppLanguage(rawValue: stored) {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.lowercased().hasPrefix("en") ? .english : .chinese
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }

    func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func time(_ date: Date) -> String {
        date.formatted(.dateTime.locale(locale).hour().minute())
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(locale).month(.abbreviated).day().year())
    }

    func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        if self == .chinese {
            if days > 0 { return "\(days)天 \(String(format: "%02d:%02d:%02d", hours, minutes, remainder))" }
            return String(format: "%02d:%02d:%02d", total / 3_600, minutes, remainder)
        }
        if days > 0 { return "\(days)d \(String(format: "%02d:%02d:%02d", hours, minutes, remainder))" }
        return String(format: "%02d:%02d:%02d", total / 3_600, minutes, remainder)
    }

    func resetTime(_ seconds: Int, date: Date) -> String {
        let calendar = Calendar.current
        let localTime = time(date)
        let day = calendar.isDateInToday(date)
            ? text("今天", "Today")
            : (calendar.isDateInTomorrow(date) ? text("明天", "Tomorrow") : shortDate(date))
        let expected = "\(day) \(localTime)"
        return text("预计 \(duration(seconds)) 后重置 · \(expected)", "Resets in \(duration(seconds)) · \(expected)")
    }

    func quotaWindowTitle(_ kind: QuotaWindowKind) -> String {
        switch (self, kind) {
        case (.chinese, .primary): return "5 小时额度"
        case (.chinese, .secondary): return "7 天额度"
        case (.english, .primary): return "5-hour limit"
        case (.english, .secondary): return "7-day limit"
        }
    }

    func quotaShortName(_ kind: QuotaWindowKind) -> String {
        switch (self, kind) {
        case (.chinese, .primary): return "5 小时"
        case (.chinese, .secondary): return "7 天"
        case (.english, .primary): return "5-hour"
        case (.english, .secondary): return "7-day"
        }
    }

    func reason(_ reason: QuotaReason) -> String {
        switch (self, reason) {
        case (.chinese, .connectionLost): return "连接失效，正在重新读取"
        case (.english, .connectionLost): return "Connection lost. Reading again."
        case (.chinese, .noSnapshot): return "尚未取得额度数据"
        case (.english, .noSnapshot): return "Quota data is not available yet."
        case (.chinese, .staleSnapshot): return "额度信息已过期，正在确认"
        case (.english, .staleSnapshot): return "Quota data is stale. Confirming again."
        case (.chinese, .bothWindowsRequired): return "需要同时确认 5 小时和 7 天额度"
        case (.english, .bothWindowsRequired): return "Both the 5-hour and 7-day limits must be confirmed."
        case (.chinese, .accountUnknown): return "无法确认当前账户范围"
        case (.english, .accountUnknown): return "The current account could not be confirmed."
        case (.chinese, .otherRestriction): return "服务端报告了其他使用限制"
        case (.english, .otherRestriction): return "The service reports another usage restriction."
        case (.chinese, .permissionUnknown): return "服务端尚未确认普通额度可用"
        case (.english, .permissionUnknown): return "The service has not confirmed standard usage availability."
        case (.chinese, .bothWindowsAvailable): return "两个额度窗口均未耗尽"
        case (.english, .bothWindowsAvailable): return "Both quota windows have remaining usage."
        case (.chinese, .resetAwaitingConfirmation): return "重置时间已到，等待服务端确认"
        case (.english, .resetAwaitingConfirmation): return "The reset time has passed. Waiting for service confirmation."
        case (.chinese, .atLeastOneWindowExhausted): return "至少一个额度窗口已耗尽"
        case (.english, .atLeastOneWindowExhausted): return "At least one quota window is exhausted."
        }
    }
}

enum AppNotice {
    case ideasUnreadable
    case resetTrackerUnavailable
    case resetSaveFailed
    case quotaReadFailed
    case draftSaved
    case draftSaveFailed
    case ideaSaved
    case ideaCopied
    case ideaEmpty
    case ideaWriteFailed
    case ideasExported
    case ideasExportFailed

    func text(in language: AppLanguage) -> String {
        switch (language, self) {
        case (.chinese, .ideasUnreadable): return "灵感文件无法读取，原文件已保留"
        case (.english, .ideasUnreadable): return "The ideas file could not be read. The original was preserved."
        case (.chinese, .resetTrackerUnavailable): return "周期重置提醒记录暂不可用"
        case (.english, .resetTrackerUnavailable): return "Reset reminders are temporarily unavailable."
        case (.chinese, .resetSaveFailed): return "周期重置提醒暂时无法保存"
        case (.english, .resetSaveFailed): return "The reset reminder could not be saved."
        case (.chinese, .quotaReadFailed): return "读取额度失败，将自动重试"
        case (.english, .quotaReadFailed): return "Could not read quota. The app will retry automatically."
        case (.chinese, .draftSaved): return "草稿已保存"
        case (.english, .draftSaved): return "Draft saved."
        case (.chinese, .draftSaveFailed): return "保存失败，内容仍在编辑框中"
        case (.english, .draftSaveFailed): return "Could not save. Your text is still in the editor."
        case (.chinese, .ideaSaved): return "已保存"
        case (.english, .ideaSaved): return "Saved."
        case (.chinese, .ideaCopied): return "已复制到剪贴板"
        case (.english, .ideaCopied): return "Copied to clipboard."
        case (.chinese, .ideaEmpty): return "先写下一点内容"
        case (.english, .ideaEmpty): return "Write something first."
        case (.chinese, .ideaWriteFailed): return "保存失败，灵感仍保留"
        case (.english, .ideaWriteFailed): return "Could not save. Your idea is still here."
        case (.chinese, .ideasExported): return "已导出灵感"
        case (.english, .ideasExported): return "Ideas exported."
        case (.chinese, .ideasExportFailed): return "导出失败"
        case (.english, .ideasExportFailed): return "Export failed."
        }
    }
}
