import AppKit

extension NSColor {
    /// A readable secondary label color that remains legible over both vibrancy materials.
    static var codexSecondaryLabel: NSColor {
        NSColor(name: "CodexUsageSecondaryLabel") { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 0.86 : 0.30, alpha: 1)
        }
    }

    static var codexCardBackground: NSColor {
        NSColor(name: "CodexUsageCardBackground") { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(calibratedWhite: 0.24, alpha: 1) : NSColor(calibratedWhite: 1, alpha: 0.72)
        }
    }

    static var codexEditorBackground: NSColor {
        NSColor(name: "CodexUsageEditorBackground") { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 0.08, alpha: 0.22)
                : NSColor(calibratedWhite: 0.10, alpha: 0.055)
        }
    }

    func codexCGColor(for appearance: NSAppearance) -> CGColor {
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance { resolved = self.cgColor }
        return resolved ?? cgColor
    }
}
