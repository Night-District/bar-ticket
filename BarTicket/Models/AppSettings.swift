import Foundation
import SwiftData

@Model
final class AppSettings {
    var isWatchingEnabled: Bool
    var aiEnabled: Bool = true
    var createdAt: Date

    init(
        isWatchingEnabled: Bool = true,
        aiEnabled: Bool = true
    ) {
        self.isWatchingEnabled = isWatchingEnabled
        self.aiEnabled = aiEnabled
        self.createdAt = Date()
    }
}
