import Foundation
import UsageCore

enum QuoteCatalog {
    static let quotes: [FamousQuote] = {
        let packagedURL = Bundle.main.resourceURL?.appendingPathComponent("CodexUsage_CodexUsage.bundle", isDirectory: true)
        let packagedBundle = packagedURL.flatMap(Bundle.init(url:))
        guard let url = packagedBundle?.url(forResource: "quotes", withExtension: "json")
                ?? Bundle.module.url(forResource: "quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(QuoteCollection.self, from: data),
              collection.validationError() == nil else {
            preconditionFailure("The bundled 99-quote library is missing or invalid.")
        }
        return collection.quotes
    }()

    static func quote(id: String?) -> FamousQuote? {
        guard let id else { return nil }
        return quotes.first { $0.id == id }
    }
}
