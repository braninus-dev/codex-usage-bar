import Foundation

/// A reset chime is valid only for a new, confirmed transition into full availability.
public enum ResetSoundPolicy {
    public static func shouldPlay(
        enabled: Bool,
        wasAvailable: Bool,
        accountChanged: Bool,
        hasConfirmedReset: Bool,
        isAvailable: Bool
    ) -> Bool {
        enabled && !wasAvailable && !accountChanged && hasConfirmedReset && isAvailable
    }
}
