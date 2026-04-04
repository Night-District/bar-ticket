import Foundation
import SwiftData
import CryptoKit

@Model
final class SeenTodo {
    @Attribute(.unique) var contentHash: String
    var filePath: String
    var lineNumber: Int
    var issueURL: String?
    var issueNumber: Int?
    var repoFullName: String?
    var title: String
    var createdAt: Date

    init(
        contentHash: String,
        filePath: String,
        lineNumber: Int,
        title: String,
        issueURL: String? = nil,
        issueNumber: Int? = nil,
        repoFullName: String? = nil
    ) {
        self.contentHash = contentHash
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.title = title
        self.issueURL = issueURL
        self.issueNumber = issueNumber
        self.repoFullName = repoFullName
        self.createdAt = Date()
    }

    /// Create a stable hash from normalized TODO content
    static func hash(content: String) -> String {
        let normalized = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
