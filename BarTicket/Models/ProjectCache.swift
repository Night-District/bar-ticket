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
    /// True if the project has at least one view with BOARD_LAYOUT (Projects v2).
    /// Kanban feature can only display projects that expose a board view.
    var hasBoardLayout: Bool = false

    init(
        projectNodeId: String,
        displayName: String,
        owner: String,
        isV2: Bool,
        projectURL: String,
        hasBoardLayout: Bool = false
    ) {
        self.projectNodeId = projectNodeId
        self.displayName = displayName
        self.owner = owner
        self.isV2 = isV2
        self.projectURL = projectURL
        self.cachedAt = Date()
        self.hasBoardLayout = hasBoardLayout
    }
}
