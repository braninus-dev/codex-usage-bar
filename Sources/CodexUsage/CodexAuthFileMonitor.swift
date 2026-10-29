import Foundation

/// Watches only auth.json metadata. Credential contents are never opened or read.
final class CodexAuthFileMonitor {
    private struct Signature: Equatable {
        let device: UInt64
        let fileNumber: UInt64
        let size: UInt64
        let modificationTime: TimeInterval
        let creationTime: TimeInterval

        static func read(at url: URL) -> Signature? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
                  let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  let modificationDate = attributes[.modificationDate] as? Date,
                  let creationDate = attributes[.creationDate] as? Date else { return nil }
            return Signature(
                device: device,
                fileNumber: fileNumber,
                size: size,
                modificationTime: modificationDate.timeIntervalSince1970,
                creationTime: creationDate.timeIntervalSince1970
            )
        }
    }

    private let authFileURL: URL
    private let interval: TimeInterval
    private let onChange: () -> Void
    private var timer: Timer?
    private var previousSignature: Signature?

    init(authFileURL: URL, interval: TimeInterval = 2, onChange: @escaping () -> Void) {
        self.authFileURL = authFileURL
        self.interval = interval
        self.onChange = onChange
        self.previousSignature = Signature.read(at: authFileURL)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChange()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChange() {
        let currentSignature = Signature.read(at: authFileURL)
        guard currentSignature != previousSignature else { return }
        previousSignature = currentSignature
        onChange()
    }
}
