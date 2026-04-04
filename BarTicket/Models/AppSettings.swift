import Foundation
import SwiftData

@Model
final class AppSettings {
    var isWatchingEnabled: Bool
    var createdAt: Date

    init(isWatchingEnabled: Bool = true) {
        self.isWatchingEnabled = isWatchingEnabled
        self.createdAt = Date()
    }
}
