import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case fallbackEnabled
    case requiresApproval
    case disabled
    case unavailable

    var isOn: Bool {
        switch self {
        case .enabled, .fallbackEnabled, .requiresApproval: return true
        case .disabled, .unavailable: return false
        }
    }

    var canOpenSettings: Bool { self == .requiresApproval }

    func message(in language: AppLanguage) -> String? {
        switch self {
        case .enabled, .disabled:
            return nil
        case .fallbackEnabled:
            return language.text("已加入本机登录项，下次登录生效", "Added to this Mac's login items; effective next login.")
        case .requiresApproval:
            return language.text("已添加，请在系统设置中允许", "Added. Allow it in System Settings.")
        case .unavailable:
            return language.text("无法读取系统状态；可点击开关重试", "System status is unavailable; toggle to retry.")
        }
    }
}

final class LaunchAtLoginManager {
    private let service = SMAppService.mainApp
    private let fallbackLabel = "local.codex.usage-bar.login"
    private let appBundleIdentifier = "local.codex.usage-bar"

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var fallbackAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(fallbackLabel).plist")
    }

    var systemStatusDescription: String { String(describing: service.status) }
    var fallbackAgentPath: String { fallbackAgentURL.path }
    var fallbackIsRequired: Bool { service.status == .notFound }

    var status: LaunchAtLoginStatus {
        if fallbackAgentIsInstalled { return .fallbackEnabled }
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .disabled
        @unknown default: return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !fallbackAgentIsInstalled else { return }
            if service.status == .notFound {
                try installFallbackAgent()
                return
            }
            do {
                try service.register()
            } catch {
                guard service.status == .notFound else { throw error }
                try installFallbackAgent()
            }
            return
        }

        if fileExists(at: fallbackAgentURL) {
            guard fallbackAgentIsInstalled else {
                throw NSError(
                    domain: "CodexUsage.LoginAtLogin",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "A different login item already uses \(fallbackAgentURL.lastPathComponent)."]
                )
            }
            try FileManager.default.removeItem(at: fallbackAgentURL)
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return
        }

        if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var fallbackAgentIsInstalled: Bool {
        guard let data = try? Data(contentsOf: fallbackAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == fallbackLabel,
              (plist["AssociatedBundleIdentifiers"] as? [String])?.contains(appBundleIdentifier) == true,
              let arguments = plist["ProgramArguments"] as? [String],
              arguments.first == Bundle.main.executableURL?.path else { return false }
        return true
    }

    private func installFallbackAgent() throws {
        if fileExists(at: fallbackAgentURL) {
            guard fallbackAgentIsInstalled else {
                throw NSError(
                    domain: "CodexUsage.LoginAtLogin",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "A different login item already uses \(fallbackAgentURL.lastPathComponent)."]
                )
            }
            return
        }
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw NSError(
                domain: "CodexUsage.LoginAtLogin",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The app must run from its packaged application bundle."]
            )
        }

        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let propertyList: [String: Any] = [
            "Label": fallbackLabel,
            "AssociatedBundleIdentifiers": [appBundleIdentifier],
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: fallbackAgentURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackAgentURL.path)
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
