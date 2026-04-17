import Foundation
import SwiftData

@Model
final class IssueTemplate {
    @Attribute(.unique) var name: String
    var templateDescription: String
    var body: String
    var isBuiltIn: Bool
    var createdAt: Date

    init(name: String, description: String, body: String, isBuiltIn: Bool = false) {
        self.name = name
        self.templateDescription = description
        self.body = body
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
    }
}
