import Foundation
import SwiftData

@Model
final class ProjectCache {
    @Attribute(.unique) var projectNodeId: String
    var displayName: String
    var owner: String
    var isV2: Bool          // true = ProjectsV2, false = Classic
    var projectURL: String
    var cachedAt: Date

    init(
        projectNodeId: String,
        displayName: String,
        owner: String,
        isV2: Bool,
        projectURL: String
    ) {
        self.projectNodeId = projectNodeId
        self.displayName = displayName
        self.owner = owner
        self.isV2 = isV2
        self.projectURL = projectURL
        self.cachedAt = Date()
    }
}
