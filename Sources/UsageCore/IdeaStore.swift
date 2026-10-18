import Foundation
import Darwin

public struct SavedIdea: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private struct IdeaDocument: Codable {
    var version: Int
    var draft: String
    var ideas: [SavedIdea]
}

public enum IdeaStoreError: Error, Equatable {
    case emptyIdea
    case unsupportedVersion(Int)
}

/// Local, device-wide idea storage. It never associates notes with a Codex account.
public struct IdeaStore {
    public static let currentVersion = 1
    public let fileURL: URL
    public private(set) var draft = ""
    public private(set) var ideas: [SavedIdea] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("local.codex.usage-bar", isDirectory: true).appendingPathComponent("ideas.json")
    }

    public mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            draft = ""
            ideas = []
            return
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(IdeaDocument.self, from: data)
        guard document.version == Self.currentVersion else {
            throw IdeaStoreError.unsupportedVersion(document.version)
        }
        draft = document.draft
        ideas = document.ideas
    }

    /// Retains the new text in memory when the disk write fails, so the editor can recover it.
    public mutating func setDraft(_ value: String) throws {
        draft = value
        try persist()
    }

    @discardableResult
    public mutating func saveIdea(_ text: String? = nil) throws -> SavedIdea {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw IdeaStoreError.emptyIdea }
        let previousDraft = draft
        let idea = SavedIdea(text: body)
        ideas.insert(idea, at: 0)
        draft = ""
        do {
            try persist()
            return idea
        } catch {
            ideas.removeAll { $0.id == idea.id }
            draft = previousDraft
            throw error
        }
    }

    public mutating func updateIdea(id: UUID, text: String) throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw IdeaStoreError.emptyIdea }
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        let previous = ideas[index]
        let previousDraft = draft
        ideas[index].text = body
        ideas[index].updatedAt = Date()
        draft = ""
        do {
            try persist()
        } catch {
            ideas[index] = previous
            draft = previousDraft
            throw error
        }
    }

    public mutating func deleteIdea(id: UUID) throws {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        let removed = ideas.remove(at: index)
        do {
            try persist()
        } catch {
            ideas.insert(removed, at: index)
            throw error
        }
    }

    public func exportJSON(to destination: URL) throws {
        let document = IdeaDocument(version: Self.currentVersion, draft: draft, ideas: ideas)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: destination, options: .atomic)
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(directory.path, mode_t(S_IRWXU)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let document = IdeaDocument(version: Self.currentVersion, draft: draft, ideas: ideas)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: fileURL, options: .atomic)
        guard chmod(fileURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
