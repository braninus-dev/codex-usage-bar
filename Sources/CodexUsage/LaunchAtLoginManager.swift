import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable

    var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .disabled, .unavailable: return false
        }
    }

    var canOpenSettings: Bool { self == .requiresApproval }

    func message(in language: AppLanguage) -> String? {
        switch self {
        case .enabled, .disabled:
            return nil
        case .requiresApproval:
            return language.text("已添加，请在系统设置中允许", "Added. Allow it in System Settings.")
        case .unavailable:
            return language.text("请从已打包的应用中更改此设置", "Change this setting from the packaged app.")
        }
    }
}

final class LaunchAtLoginManager {
    private var service: SMAppService { .mainApp }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .disabled): try service.register()
        case (false, .enabled), (false, .requiresApproval): try service.unregister()
        default: break
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
