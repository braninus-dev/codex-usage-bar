import AppKit
import QuartzCore

/// Cropped artwork from the approved 10-second concept loop, kept separate from
/// live labels and controls so quota state and actions remain accessible.
public final class StarfieldAnimationView: NSView {
    public enum PresentationState: Equatable {
        case fullAvailable
        case partialOrUnknown
    }

    public var presentationState: PresentationState = .fullAvailable {
        didSet { updateArtwork() }
    }

    /// Optional override used by static previews; production follows macOS.
    public var reduceMotionOverride: Bool? {
        didSet { updatePlayback() }
    }

    private let artworkView = NSImageView(frame: .zero)
    private let corePulseLayer = CAGradientLayer()
    private let fullArtwork = StarfieldAnimationView.loadArtwork(named: "StellarFull")
    private let partialArtwork = StarfieldAnimationView.loadArtwork(named: "StellarPartial")
    private var accessibilityObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    private static func loadArtwork(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "gif") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 14

        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.imageAlignment = .alignCenter
        artworkView.animates = true
        artworkView.setAccessibilityElement(false)
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artworkView)
        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            artworkView.topAnchor.constraint(equalTo: topAnchor),
            artworkView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        corePulseLayer.type = .radial
        corePulseLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        corePulseLayer.endPoint = CGPoint(x: 1, y: 1)
        corePulseLayer.colors = [
            NSColor(srgbRed: 1, green: 0.91, blue: 0.70, alpha: 0.92).cgColor,
            NSColor(srgbRed: 0.60, green: 0.78, blue: 1, alpha: 0.32).cgColor,
            NSColor.clear.cgColor,
        ]
        corePulseLayer.locations = [0, 0.32, 1]
        corePulseLayer.opacity = 0
        layer?.addSublayer(corePulseLayer)

        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updatePlayback() }

        updateArtwork()
    }

    public override func layout() {
        super.layout()
        corePulseLayer.frame = CGRect(x: bounds.midX - 42, y: bounds.midY - 42, width: 84, height: 84)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.updatePlayback() }
        }
        updatePlayback()
    }

    private var shouldReduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var isEffectivelyVisible: Bool {
        guard let window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor else { return false }
        return true
    }

    private func updateArtwork() {
        artworkView.animates = false
        artworkView.image = presentationState == .fullAvailable ? fullArtwork : partialArtwork
        updatePlayback()
    }

    private func updatePlayback() {
        artworkView.animates = !shouldReduceMotion && isEffectivelyVisible
    }

    public func refreshMotionPreference() {
        updatePlayback()
    }

    /// A brief independent core lift pairs a confirmed reset with the saved idea.
    public func pulseCoreOnce() {
        guard !shouldReduceMotion else { return }
        corePulseLayer.removeAllAnimations()

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.92, 0]
        opacity.keyTimes = [0, 0.38, 1]
        opacity.duration = 0.78

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.82, 1.18, 1]
        scale.keyTimes = [0, 0.38, 1]
        scale.duration = 0.78

        let pulse = CAAnimationGroup()
        pulse.animations = [opacity, scale]
        pulse.duration = 0.78
        pulse.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        pulse.isRemovedOnCompletion = true
        corePulseLayer.add(pulse, forKey: "confirmedResetPulse")
    }
}
