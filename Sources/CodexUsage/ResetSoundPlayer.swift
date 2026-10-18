import AppKit

/// Plays the locally bundled reset chime without taking focus or changing system volume.
final class ResetSoundPlayer {
    static let shared = ResetSoundPlayer()

    private var activeSound: NSSound?

    func play() {
        guard let url = Bundle.module.url(forResource: "codex_starlight_restored", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        sound.volume = 0.55
        activeSound = sound
        sound.play()
    }
}
