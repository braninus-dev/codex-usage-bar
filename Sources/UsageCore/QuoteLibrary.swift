import Foundation

public struct FamousQuote: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let theme: String
    public let authorChinese: String
    public let authorEnglish: String
    public let workChinese: String
    public let workEnglish: String
    public let locator: String
    public let locatorChinese: String
    public let textChinese: String
    public let textEnglish: String
    public let sourceURL: URL
    public let translationChinese: String?
    public let translationEnglish: String?
    public let sourceExcerpt: String
    public let sourceTextLanguage: String

    public init(
        id: String,
        theme: String,
        authorChinese: String,
        authorEnglish: String,
        workChinese: String,
        workEnglish: String,
        locator: String,
        locatorChinese: String,
        textChinese: String,
        textEnglish: String,
        sourceURL: URL,
        translationChinese: String? = nil,
        translationEnglish: String? = nil,
        sourceExcerpt: String,
        sourceTextLanguage: String
    ) {
        self.id = id
        self.theme = theme
        self.authorChinese = authorChinese
        self.authorEnglish = authorEnglish
        self.workChinese = workChinese
        self.workEnglish = workEnglish
        self.locator = locator
        self.locatorChinese = locatorChinese
        self.textChinese = textChinese
        self.textEnglish = textEnglish
        self.sourceURL = sourceURL
        self.translationChinese = translationChinese
        self.translationEnglish = translationEnglish
        self.sourceExcerpt = sourceExcerpt
        self.sourceTextLanguage = sourceTextLanguage
    }
}

public struct QuoteCollection: Codable, Equatable, Sendable {
    public let quotes: [FamousQuote]
    public init(quotes: [FamousQuote]) { self.quotes = quotes }

    public func validationError() -> String? {
        guard quotes.count == 99 else { return "Quote collection must contain exactly 99 entries." }
        guard Set(quotes.map(\.id)).count == 99 else { return "Quote IDs must be unique." }
        for quote in quotes {
            guard !quote.id.isEmpty, !quote.authorChinese.isEmpty, !quote.authorEnglish.isEmpty,
                  !quote.workChinese.isEmpty, !quote.workEnglish.isEmpty, !quote.locator.isEmpty, !quote.locatorChinese.isEmpty,
                  !quote.textChinese.isEmpty, !quote.textEnglish.isEmpty, !quote.sourceExcerpt.isEmpty,
                  quote.sourceTextLanguage == "zh" || quote.sourceTextLanguage == "en",
                  quote.sourceURL.scheme == "https" else {
                return "Quote \(quote.id) is missing required attribution or source data."
            }
        }
        return nil
    }
}

/// Persistable Fisher–Yates shuffle bag that prevents a duplicate at bag boundaries.
public struct QuoteShuffleBag: Codable, Equatable, Sendable {
    public private(set) var remainingIDs: [String]
    public private(set) var previousID: String?

    public init(remainingIDs: [String] = [], previousID: String? = nil) {
        self.remainingIDs = remainingIDs
        self.previousID = previousID
    }

    public mutating func nextID(from identifiers: [String], using generator: inout some RandomNumberGenerator) -> String? {
        var seen = Set<String>()
        let validIDs = identifiers.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !validIDs.isEmpty else { return nil }

        let validSet = Set(validIDs)
        remainingIDs = remainingIDs.filter { validSet.contains($0) }
        if remainingIDs.isEmpty {
            var shuffled = validIDs
            guard shuffled.count > 1 else {
                remainingIDs = shuffled
                return drawLast()
            }
            for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
                let other = Int.random(in: 0...index, using: &generator)
                shuffled.swapAt(index, other)
            }
            if shuffled.last == previousID {
                shuffled.swapAt(shuffled.count - 1, shuffled.count - 2)
            }
            remainingIDs = shuffled
        }
        return drawLast()
    }

    private mutating func drawLast() -> String? {
        guard let value = remainingIDs.popLast() else { return nil }
        previousID = value
        return value
    }
}
